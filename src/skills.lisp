(in-package #:photo-ai-lisp)

(defvar *skills-root* (merge-pathnames ".agents/skills/" (user-homedir-pathname)))

(define-condition skill-error (error)
  ((skill-name :initarg :skill-name :reader skill-error-name)
   (stderr     :initarg :stderr     :reader skill-error-stderr)
   (exit-code  :initarg :exit-code  :reader skill-error-exit-code))
  (:report (lambda (c s)
             (format s "Skill ~A failed (exit ~A): ~A"
                     (skill-error-name c)
                     (skill-error-exit-code c)
                     (skill-error-stderr c)))))

(defun skill-script-path (skill-name)
  "Find the first .py file under ~/.agents/skills/<skill-name>/scripts/."
  (let* ((scripts-dir (merge-pathnames (format nil "~A/scripts/" skill-name) *skills-root*))
         (scripts (directory (merge-pathnames "*.py" scripts-dir))))
    (or (first scripts)
        (error 'skill-error
               :skill-name skill-name
               :stderr (format nil "No .py script found in ~A" scripts-dir)
               :exit-code -1))))

(defun run-skill (skill-name &rest args)
  "Run a skill script as subprocess. Returns parsed JSON (yason object) or signals skill-error."
  (let* ((script (namestring (skill-script-path skill-name)))
         (python (if (uiop:os-windows-p) "python" "python3")))
    (multiple-value-bind (stdout stderr exit-code)
        (uiop:run-program (list* python script args)
                          :output :string
                          :error-output :string
                          :ignore-error-status t)
      (unless (zerop exit-code)
        (error 'skill-error :skill-name skill-name :stderr stderr :exit-code exit-code))
      (yason:parse stdout))))
