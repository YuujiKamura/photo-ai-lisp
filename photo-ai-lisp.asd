(defsystem "photo-ai-lisp"
  :version "0.0.1"
  :description "Lisp orchestrator for construction photo pipeline"
  :license "MIT"
  :depends-on ("hunchentoot" "hunchensocket" "cl-who" "bordeaux-threads")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "proc")
                             (:file "agent")
                             (:file "case")
                             (:file "term")
                             (:file "main")))))

(defsystem "photo-ai-lisp/tests"
  :depends-on ("photo-ai-lisp" "fiveam")
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "agent-scenario")
                             (:file "proc-scenario")
                             (:file "proc-tests")
                             (:file "term-tests")
                             (:file "main-tests")
                             (:file "agent-tests")
                             (:file "term-coverage-tests")
                             (:file "main-coverage-tests")
                             (:file "case-tests"))))
  :perform (test-op (o c)
             (uiop:symbol-call '#:photo-ai-lisp/tests '#:run-tests)))
