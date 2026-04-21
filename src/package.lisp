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
           #:*ghostty-web-url*
           ;; issue #17 — CP (Control Plane) client
           #:cp-command
           #:cp-parse-response
           #:make-cp-input
           #:make-cp-tail
           #:make-cp-state
           #:make-cp-list-tabs
           #:connect-cp
           #:disconnect-cp
           #:send-cp-command
           #:cp-tail
           #:cp-input
           #:wait-for-completion
           #:invoke-via-cp
           ;; issue #30 Phase 2 (G1.b) — pending-request table public surface
           #:cp-request-timeout
           #:cp-request-timeout-msg-id
           #:cp-request-timeout-timeout
           #:*cp-default-timeout*
           ;; issue #19 — T2.b: CP UI bridge
           #:*demo-session-id*
           #:*demo-cp-client*
           #:input-bridge-handler
           ;; issue #19 — T2.c: demo session spawn utility
           #:parse-demo-session-name
           ;; issue #29 — C1: usage log auto-write
           #:*usage-log-path*
           #:*usage-errors-log-path*
           #:write-usage-log-event))
