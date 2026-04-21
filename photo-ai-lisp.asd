(defsystem "photo-ai-lisp"
  :version "0.0.1"
  :description "Lisp orchestrator for construction photo pipeline"
  :license "MIT"
  :depends-on ("hunchentoot" "hunchensocket" "cl-who" "bordeaux-threads" "cl-base64" "websocket-driver" "shasht" "uuid" "local-time")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "proc")
                             (:file "agent")
                             (:file "case")
                             (:file "pipeline")
                             (:file "pipeline-cp")
                             (:file "business-ui")
                             (:file "presets")
                             (:file "live-repl")
                             (:file "cp-protocol")
                             (:file "cp-client")
                             (:file "term")
                             (:file "usage-log")
                             (:file "cp-ui-bridge")
                             (:file "control")
                             (:file "main")))))

(defsystem "photo-ai-lisp/tests"
  :depends-on ("photo-ai-lisp" "fiveam" "drakma")
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "agent-scenario")
                             (:file "proc-scenario")
                             (:file "proc-tests")
                             (:file "proc-integration-tests")
                             (:file "term-tests")
                             (:file "vendor-mime-tests")
                             (:file "vendor-handler-tests")
                             (:file "main-tests")
                             (:file "agent-tests")
                             (:file "cp-protocol-tests")
                             (:file "cp-client-tests")
                             (:file "pipeline-cp-tests")
                             (:file "presets-tests")
                             (:file "business-ui-tests")
                             (:file "cp-ui-bridge-tests")
                             (:file "usage-log-tests")
                             (:file "shell-trace-tests")
                             (:file "reload-tests")
                             (:file "inject-tests")
                             (:file "inject-e2e-scenario")
                             (:file "live-repl-tests")
                             (:file "e2e-tests"))))
  :perform (test-op (o c)
             (uiop:symbol-call '#:photo-ai-lisp/tests '#:run-tests)))
