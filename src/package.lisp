(defpackage #:photo-ai-lisp
  (:use #:cl #:hunchentoot #:cl-who)
  (:shadow #:start #:stop)
  (:export #:start #:stop
           ;; policy #01 — case CLOS model (stubs; implementation pending)
           #:photo-case
           #:make-photo-case
           #:photo-case-path
           #:photo-case-name
           #:photo-case-masters-dir
           #:photo-case-reference-path
           #:case-from-directory
           #:find-case
           #:*sessions*
           #:register-session
           #:lookup-session
           #:clear-session
           #:build-case-env
           #:parse-shell-case-query
           #:api-session-handler))
