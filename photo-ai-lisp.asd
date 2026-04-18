(defsystem "photo-ai-lisp"
  :version "0.0.1"
  :description "Lisp orchestrator for construction photo pipeline"
  :license "MIT"
  :depends-on ("hunchentoot" "hunchensocket" "cl-who")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "agent")
                             (:file "term")
                             (:file "main")))))

(defsystem "photo-ai-lisp/tests"
  :depends-on ("photo-ai-lisp" "fiveam")
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "agent-scenario"))))
  :perform (test-op (o c)
             (uiop:symbol-call '#:photo-ai-lisp/tests '#:run-tests)))
