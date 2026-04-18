(in-package #:photo-ai-lisp)

(defmacro layout (title &body body)
  `(with-html-output-to-string (s nil :prologue t)
     (:html
      (:head (:title (str ,title)))
      (:body
       (:header :style "margin-bottom: 1rem"
        (:h1 "photo-ai-lisp")
        (:p (:a :href "/" "Home") " | " (:a :href "/upload" "Upload") " | " (:a :href "/scan" "Scan") " | " (:a :href "/manifest" "Manifest")))
       ,@body
       (:footer :style "margin-top: 1rem" (:small "Viaweb-style live edit prototype"))))))
