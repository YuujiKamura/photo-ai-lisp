(defpackage #:photo-ai-lisp
  (:use #:cl #:hunchentoot #:cl-who)
  (:export #:start #:stop
           #:photo #:photo-id #:photo-path #:photo-category #:photo-uploaded-at
           #:add-photo #:all-photos #:find-photo #:set-photo-category))
