(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(defmacro with-stub-skill (skill-name script-content &body body)
  "Create a temporary skills root with a stub .py for skill-name."
  (let ((root-var (gensym "ROOT"))
        (old-root-var (gensym "OLD")))
    `(uiop:with-temporary-directory (:pathname ,root-var)
       (let* ((scripts-dir (merge-pathnames (format nil "~A/scripts/" ,skill-name) ,root-var))
              (script-file (merge-pathnames "stub.py" scripts-dir))
              (,old-root-var photo-ai-lisp::*skills-root*))
         (ensure-directories-exist scripts-dir)
         (uiop:with-output-file (f script-file)
           (write-string ,script-content f))
         (setf photo-ai-lisp::*skills-root* ,root-var)
         (unwind-protect (progn ,@body)
           (setf photo-ai-lisp::*skills-root* ,old-root-var))))))

(test skill-script-path-finds-py
  (with-stub-skill "test-skill" "# stub"
    (let ((p (skill-script-path "test-skill")))
      (is (pathnamep p))
      (is (string= "py" (pathname-type p))))))

(test skill-script-path-signals-error-when-empty
  (uiop:with-temporary-directory (:pathname root)
    (let ((scripts-dir (merge-pathnames "empty-skill/scripts/" root))
          (old photo-ai-lisp::*skills-root*))
      (ensure-directories-exist scripts-dir)
      (setf photo-ai-lisp::*skills-root* root)
      (unwind-protect
           (signals skill-error (skill-script-path "empty-skill"))
        (setf photo-ai-lisp::*skills-root* old)))))

(test run-skill-success
  (with-stub-skill "ok-skill" "import sys; sys.stdout.write('{\"ok\": true}')"
    (let ((result (run-skill "ok-skill")))
      (is (not (null result))))))

(test run-skill-error
  (with-stub-skill "fail-skill" "import sys; sys.stderr.write('boom'); sys.exit(1)"
    (signals skill-error (run-skill "fail-skill"))))
