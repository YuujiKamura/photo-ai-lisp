(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(defun make-temp-dir ()
  "Create a uniquely-named subdir under the OS temp dir and return its pathname."
  (let* ((base (uiop:temporary-directory))
         (dir  (merge-pathnames
                (format nil "photo-ai-lisp-test-~A-~A/"
                        (get-universal-time) (random 100000))
                base)))
    (ensure-directories-exist dir)
    dir))

(defmacro with-temp-skills-root ((root-var) &body body)
  "Bind ROOT-VAR to a fresh temp dir and restore *skills-root* on exit."
  (let ((old-var (gensym "OLD")))
    `(let ((,root-var (make-temp-dir))
           (,old-var photo-ai-lisp::*skills-root*))
       (unwind-protect
            (progn
              (setf photo-ai-lisp::*skills-root* ,root-var)
              ,@body)
         (setf photo-ai-lisp::*skills-root* ,old-var)
         (ignore-errors (uiop:delete-directory-tree ,root-var :validate t))))))

(defmacro with-stub-skill (skill-name script-content &body body)
  "Create a temporary skills root with a stub .py for skill-name."
  (let ((root-var (gensym "ROOT")))
    `(with-temp-skills-root (,root-var)
       (let* ((scripts-dir (merge-pathnames (format nil "~A/scripts/" ,skill-name) ,root-var))
              (script-file (merge-pathnames "stub.py" scripts-dir)))
         (ensure-directories-exist scripts-dir)
         (with-open-file (f script-file :direction :output :if-exists :supersede)
           (write-string ,script-content f))
         ,@body))))

(test skill-script-path-finds-py
  (with-stub-skill "test-skill" "# stub"
    (let ((p (skill-script-path "test-skill")))
      (is (pathnamep p))
      (is (string= "py" (pathname-type p))))))

(test skill-script-path-signals-error-when-empty
  (with-temp-skills-root (root)
    (let ((scripts-dir (merge-pathnames "empty-skill/scripts/" root)))
      (ensure-directories-exist scripts-dir)
      (signals skill-error (skill-script-path "empty-skill")))))

(test run-skill-success
  (with-stub-skill "ok-skill" "import sys; sys.stdout.write('{\"ok\": true}')"
    (let ((result (run-skill "ok-skill")))
      (is (not (null result))))))

(test run-skill-error
  (with-stub-skill "fail-skill" "import sys; sys.stderr.write('boom'); sys.exit(1)"
    (signals skill-error (run-skill "fail-skill"))))
