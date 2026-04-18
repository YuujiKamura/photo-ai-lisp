(in-package #:photo-ai-lisp)

(defstruct photo
  (id 0 :type integer)
  (path "" :type string)
  (category :unclassified :type keyword)
  (uploaded-at (get-universal-time) :type integer))
