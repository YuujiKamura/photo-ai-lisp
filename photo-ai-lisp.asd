(defsystem "photo-ai-lisp"
  :version "0.0.1"
  :description "Viaweb-style construction photo manifest app in Common Lisp"
  :license "MIT"
  :depends-on ("hunchentoot" "cl-who" "cl-store")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "models")
                             (:file "storage")
                             (:file "views")
                             (:file "main")))))
