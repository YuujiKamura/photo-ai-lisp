(in-package #:photo-ai-lisp)

;;; Preset registry — the allowlist that the UI can invoke.
;;;
;;; Every button in the browser that fires a subprocess must go through
;;; a named preset defined here. Unknown names are refused by run-preset.
;;; This is the 'rule layer' for side-effect containment.
;;;
;;; DSL: (defpreset <name> "arg0" "arg1" ...) registers one entry.
;;; No free-form shell interpolation — args pass to uiop:launch-program
;;; as a list, so no shell metacharacter expansion happens.

(defvar *presets* (make-hash-table :test 'equal)
  "Name (string) → list of argv strings. Populated by DEFPRESET.")

(defmacro defpreset (name &rest argv)
  "Register a preset under NAME (keyword or string) with ARGV as the
   command to run. Stored at macroexpansion-free call time so REPL
   redefinition just overwrites the entry."
  `(setf (gethash ,(string-downcase (string name)) *presets*)
         (list ,@argv)))

(defun find-preset (name)
  "Look up NAME (any case) in the preset registry. Returns the argv
   list or NIL if unknown."
  (gethash (string-downcase (string name)) *presets*))

(defun list-preset-names ()
  "All registered preset names, sorted."
  (let (names)
    (maphash (lambda (k _v) (declare (ignore _v)) (push k names)) *presets*)
    (sort names #'string<)))

(defun %destructive-token-p (token)
  "Reject tokens that look destructive at registration time. This is a
   weak static check, not a sandbox — the real discipline is only
   registering safe commands in DEFPRESET forms."
  (let ((down (string-downcase token)))
    (or (search "rm " down)
        (search "del " down)
        (search " format " down)
        (search "shutdown" down)
        (search "drop " down))))

(defun run-preset (name)
  "Execute the preset registered under NAME. Returns a plist:
     (:name :argv :stdout :exit-code)
   Signals (error) when NAME is not registered."
  (let ((argv (find-preset name)))
    (unless argv
      (error "unknown preset: ~a" name))
    (when (some #'%destructive-token-p argv)
      (error "preset ~a contains a destructive token; refusing" name))
    (multiple-value-bind (out err code)
        (uiop:run-program argv
                          :output :string
                          :error-output :output
                          :ignore-error-status t)
      (declare (ignore err))
      (list :name name
            :argv argv
            :stdout (or out "")
            :exit-code code))))

;; ---- bundled presets -----------------------------------------------------

(defpreset "hello"
  (if (uiop:os-windows-p) "cmd.exe" "/bin/sh")
  (if (uiop:os-windows-p) "/c" "-c")
  "echo hello from photo-ai-lisp")

(defpreset "skills-list"
  (if (uiop:os-windows-p) "cmd.exe" "/bin/sh")
  (if (uiop:os-windows-p) "/c" "-c")
  "dir /b C:\\Users\\yuuji\\.agents\\skills\\photo-* 2>NUL || ls -1 ~/.agents/skills/photo-* 2>/dev/null || echo (no skills found)")

;; ---- HTTP handler --------------------------------------------------------

(defun %preset-result->json (result)
  "Convert a run-preset plist into a JSON string."
  (format nil "{\"name\":\"~a\",\"argv\":[~{\"~a\"~^,~}],\"stdout\":\"~a\",\"exit_code\":~a}"
          (%json-escape (or (getf result :name) ""))
          (mapcar #'%json-escape (or (getf result :argv) '()))
          (%json-escape (or (getf result :stdout) ""))
          (or (getf result :exit-code) 0)))

(defun run-preset-handler (name)
  "HTTP handler body for GET /api/run/:name. Returns the JSON-encoded
   preset execution result, or an error envelope with explain text."
  (handler-case
      (%preset-result->json (run-preset name))
    (error (e)
      (format nil "{\"error\":\"~a\"}" (%json-escape (princ-to-string e))))))

(defun list-presets-handler ()
  "HTTP handler body for GET /api/presets. Returns a JSON array of
   {name, argv} so the UI can render buttons dynamically."
  (let ((objs
          (loop for name in (list-preset-names)
                for argv = (find-preset name)
                collect (format nil "{\"name\":\"~a\",\"argv\":[~{\"~a\"~^,~}]}"
                                (%json-escape name)
                                (mapcar #'%json-escape argv)))))
    (format nil "[~{~a~^,~}]" objs)))
