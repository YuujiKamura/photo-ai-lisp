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
           #:api-session-handler
           ;; policy #02 — pipeline DSL (stubs; implementation pending)
           #:*skills*
           #:skill
           #:make-skill
           #:skill-name
           #:skill-describe
           #:skill-invoke
           #:register-skill
           #:find-skill
           #:unregister-skill
           #:*pipelines*
           #:pipeline
           #:defpipeline
           #:find-pipeline
           #:pipeline-name
           #:pipeline-steps
           #:pipeline-result
           #:run-pipeline
           #:pipeline-result-success-p
           #:pipeline-result-steps
           #:pipeline-result-final-output
           #:pipeline-result-failure-index
           ;; policy #04 — business UI skeleton (stubs; implementation pending)
           #:*case-root*
           #:scan-cases
           #:case-id
           #:case-from-id
           #:list-cases-handler
           #:case-view-handler
           #:home-handler
           ;; issue #17 — CP (Control Plane) client
           #:cp-command
           #:cp-parse-response
           #:make-cp-input
           #:make-cp-tail
           #:make-cp-state
           #:make-cp-list-tabs))
