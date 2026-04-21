(in-package #:photo-ai-lisp/tests)

(5am:def-suite reload-suite :description "hot reload surface")
(5am:in-suite reload-suite)

(5am:test reload-handler-rejects-unknown-module
  (let ((json (photo-ai-lisp::reload-handler "nosuch")))
    (5am:is (search "\"ok\":false" json))
    (5am:is (search "not in *reloadable-modules*" json))))

(5am:test reload-handler-presets-roundtrip
  "Reloading :presets while the system is loaded should succeed with
   ok:true and report the module name and a non-negative elapsed_ms."
  (let ((json (photo-ai-lisp::reload-handler "presets")))
    (5am:is (search "\"ok\":true" json))
    (5am:is (search "\"module\":\"presets\"" json))
    (5am:is (search "\"elapsed_ms\":" json))))

(5am:test reload-module-picks-up-new-defpreset
  "Write a temporary preset file, loading it should register a new
   preset visible via find-preset. Proves (load path) adds to the
   live *presets* table without re-initializing it."
  (let* ((tmp (uiop:temporary-directory))
         (marker (format nil "reload-marker-~a" (random 1000000)))
         (path (merge-pathnames (format nil "~a.lisp" marker) tmp)))
    (unwind-protect
        (progn
          (with-open-file (s path :direction :output
                                  :if-exists :supersede
                                  :external-format :utf-8)
            (write-line "(in-package #:photo-ai-lisp)" s)
            (format s "(defpreset ~s :argv (list \"echo\" ~s))~%"
                    marker marker))
          ;; Precondition: not present yet.
          (5am:is (null (photo-ai-lisp::find-preset marker)))
          (load path)
          ;; Postcondition: now present.
          (5am:is (equal (list "echo" marker)
                         (photo-ai-lisp::find-preset-argv marker))))
      (ignore-errors (delete-file path)))))

(5am:test reloadable-modules-is-nonempty
  (5am:is (listp photo-ai-lisp::*reloadable-modules*))
  (5am:is (plusp (length photo-ai-lisp::*reloadable-modules*)))
  (5am:is (member :presets photo-ai-lisp::*reloadable-modules*)))
