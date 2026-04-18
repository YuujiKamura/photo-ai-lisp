(defsystem "photo-ai-lisp"
  :version "0.0.1"
  :description "Viaweb-style construction photo manifest app in Common Lisp"
  :license "MIT"
  :depends-on ("hunchentoot" "cl-who" "cl-store" "yason" "bordeaux-threads")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "models")
                             (:file "storage")
                             (:file "skills")
                             (:file "pipeline")
                             (:file "views")
                             (:file "main")))))

(defsystem "photo-ai-lisp/tests"
  :depends-on ("photo-ai-lisp" "fiveam")
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "main")
                             (:file "models-tests")
                             (:file "storage-tests")
                             (:file "views-tests")
                             (:file "skills-tests")
                             (:file "pipeline-tests")
                             (:file "main-tests"))))
  :perform (test-op (o c)
             (uiop:symbol-call '#:photo-ai-lisp/tests '#:run-tests)))
