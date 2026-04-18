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
