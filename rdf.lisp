(in-package :cl-conllu)

;; from Wilbur2
(defun components->string (components)
  (with-output-to-string (stream)
    (dolist (component components)
      (princ component stream))))

;; from Wilbur2
(defun escape-string (string char-escape-function)
  ;; This tries to be clever about stuff that does not need to be escaped
  (labels ((escape (s n i parts)
             (let ((j (position-if char-escape-function s :start i)))
               (cond (j (escape s n (1+ j)
                                (list* (funcall char-escape-function (char s j))
                                       (subseq s i j)
                                       parts)))
                     (parts (components->string (nreverse (cons (subseq s i) parts))))
                     (t s)))))
    (escape string (length string) 0 nil)))

;; from Wilbur2
(defun escape-turtle-char (char)
  (cdr (assoc char '((#\\ . "\\\\")
                     (#\" . "\\\"")
                     (#\Linefeed . "\\n")
                     (#\Return . "\\r")
                     (#\Tab . "\\t"))
              :test #'char=)))

(defun unspecified-field? (c)
  (string-equal c "_"))

(defun make-literal (string)
  (format nil "\"~a\"" (escape-string string #'escape-turtle-char)))

(defun make-token-id (sentence-id token-id)
  (format nil "~at~a" sentence-id token-id))

(defun make-upos (upos)
  (format nil "conll:~a" (string-capitalize upos)))

(defun make-dep (dep)
  (format nil "conll:d~a" dep))

(defun make-featurename (feat)
  (format nil "conll:f~a" (string-downcase feat)))

(defun make-metadata (metadata)
  (format nil "~{ ~a ~}"
          (mapcar (lambda (m)
                    (format nil "[ conll:metadata-key ~a ; conll:metadata-value ~a ]" (make-literal (car m)) (make-literal (cdr m)))) metadata)))

(defun make-features (features &optional (value-as-literal nil))
  (unless (unspecified-field? features)
    (with-output-to-string (s)
      (mapc (lambda (f)
              (destructuring-bind (name value) (split-sequence #\= f)
                (format s "conll:~a a conll:FeatureName . ~%" (make-featurename name))
                (format s "conll:~a rdfs:label ~a . ~%" (make-featurename name) (make-literal name))
                (unless value-as-literal
                  (format s "conll:~a a conll:FeatureValue .~%" value)
                  (format s "conll:~a rdfs:label ~a .~%" value (make-literal value))))) 
            (split-sequence #\| features :remove-empty-subseqs t))
      s)))

(defun make-features-bnode (features &optional (value-as-literal nil))
  (unless (unspecified-field? features)
    (format nil "~{ ~a~^;~}" 
            (mapcar (lambda (f)
                      (destructuring-bind (name value) (split-sequence #\= f)
                        (if value-as-literal
                            (format nil "conll:~a ~a" (make-featurename name) (make-literal value))
                            (format nil "conll:~a conll:~a" (make-featurename name) value)))) 
                    (split-sequence #\| features :remove-empty-subseqs t)))))

(defun convert-sentence-to-turtle (stream conll text id)
  (format stream "conll:root a conll:DepRel .~%")
  (format stream "conll:root rdfs:label ~a .~%" (make-literal "root"))

  (format stream "conll:~a a conll:Sentence .~%" id)
  (format stream "conll:~a rdfs:label ~a .~%" id (make-literal text))
  (format stream "conll:~a conll:tokens (~{~a~^ ~}) .~%" id 
   (mapcar (lambda (tk) (format nil "conll:~a" (make-token-id id (slot-value tk 'id)))) (sentence-tokens conll)))
  (format stream "conll:~a conll:metadata ( ~a ) .~%" id (make-metadata (sentence-meta conll)))
  (dolist (tk (sentence-tokens conll))
    (let ((tid (make-token-id id (slot-value tk 'id)))
          (form (slot-value tk 'form))
          (lemma (slot-value tk 'lemma))
          (upostag (slot-value tk 'upostag))
          (xpostag (slot-value tk 'xpostag))
          (feats (make-features-bnode (slot-value tk 'feats)))
          (head (make-token-id id (slot-value tk 'head)))
          (deprel (slot-value tk 'deprel))
          (deps (slot-value tk 'deps))
          (misc (make-features-bnode (slot-value tk 'misc) t)))
      (format stream "conll:~a a conll:Token .~%" tid)
      (format stream "conll:~a conll:sentence conll:~a .~%" tid id)
      (format stream "conll:~a conll:form ~a .~%" tid (make-literal form))
      (format stream "conll:~a conll:lemma ~a .~%" tid (make-literal lemma))
      (format stream "conll:~a conll:upos ~a .~%" tid (make-upos upostag))
      (format stream "~a a conll:UPostag .~%" (make-upos upostag))
      (format stream "~a rdfs:label ~a .~%" (make-upos upostag) (make-literal upostag))

      ;; we append -raw to these as we don't have a good way of
      ;; converting them to "proper" RDF
      (unless (unspecified-field? xpostag)
       (format stream "conll:~a conll:xpos-raw ~a .~%" tid (make-literal xpostag)))
      (unless (unspecified-field? deps)
       (format stream "conll:~a conll:deps-raw ~a .~%" tid (make-literal deps)))

      (when misc
       (format stream "conll:~a conll:misc [ ~a ] .~%" tid misc))

      (when feats
        (format stream "~a" (make-features (slot-value tk 'feats)))
        (format stream "conll:~a conll:features [ ~a ] .~%" tid feats))
      (if (string-equal "root" deprel)
          (format stream "conll:~a conll:root conll:~a .~%" id tid)
          (progn 
            (format stream "~a a conll:DepRel .~%" (make-dep deprel))
            (format stream "~a rdfs:label ~a .~%" (make-dep deprel) (make-literal deprel))
            (format stream "conll:~a ~a conll:~a .~%" tid (make-dep deprel) head)
            (format stream "conll:~a ~a conll:~a .~%" tid (make-dep deprel) head))))))

(defun convert-conll (stream conlls text-fn id-fn)
  "Converts the collection of sentences (as generated by READ-CONLLU)
in CONLL, using the function TEXT-FN to extract the text of each
sentence and ID-FN to extract the id of each sentence (we need this as
there is no standardized way of knowing this.)"
  (format stream "@prefix conll: <http://br.ibm.com/conll/> . @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> . @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> . @prefix dc: <http://purl.org/dc/elements/1.1/> . @prefix dcterms: <http://purl.org/dc/terms/> . @prefix skos: <http://www.w3.org/2004/02/skos/core#> . @prefix owl: <http://www.w3.org/2002/07/owl#> .")

  (dolist (c conlls)
    (convert-sentence-to-turtle stream c (funcall text-fn c) (funcall id-fn c))))