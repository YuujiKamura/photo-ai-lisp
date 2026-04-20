(in-package #:photo-ai-lisp)

;;; Preset registry — the allowlist the UI injects into the live terminal.
;;;
;;; Each preset is a named list of argv tokens. The UI joins them with
;;; spaces + CR and postMessages the result into the /shell iframe, where
;;; xterm.js forwards it over /ws/shell into the already-running shell
;;; (cmd.exe on Windows, bash on Unix). No server-side subprocess spawn
;;; happens here — the injected text runs inside the shell the user is
;;; already looking at.
;;;
;;; Contract with the front end:
;;;   preset argv must be a safe command line as typed in the target
;;;   shell. No shell metacharacters beyond what you would type
;;;   intentionally. CR is appended client-side to trigger execution.
;;;
;;; DSL: (defpreset <name> "arg0" "arg1" ...) registers one entry.

(defvar *presets* (make-hash-table :test 'equal)
  "Name (string) → list of argv strings. Populated by DEFPRESET.")

(defmacro defpreset (name &rest argv)
  "Register a preset under NAME (keyword or string) with ARGV as the
   argv tokens to inject into the terminal. REPL re-evaluation just
   overwrites the existing entry."
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

;; ---- bundled presets -----------------------------------------------------
;;
;; Each preset is the plain command line a user would type into the
;; running shell. OS dispatch happens via uiop:os-windows-p at
;; macroexpansion so REPL redefinition still works.

(defpreset "hello"
  "echo" "hello" "from" "photo-ai-lisp")

(defpreset "skills-list"
  (if (uiop:os-windows-p)
      "dir"
      "ls")
  (if (uiop:os-windows-p)
      "C:\\Users\\yuuji\\.agents\\skills\\"
      "~/.agents/skills/"))

(defpreset "date"
  (if (uiop:os-windows-p)
      "echo"
      "date")
  (if (uiop:os-windows-p)
      "%DATE%"
      "+%Y-%m-%dT%H:%M:%S"))

;; ---- hot reload ----------------------------------------------------------

(defvar *reloadable-modules*
  '(:proc :presets :business-ui :term :control :main)
  "Source module keywords that /api/reload can hot-swap. Keys map to
   files under src/ via the naming convention src/<key>.lisp.")

;; Observer registry. Any module that wants to react to a module reload
;; (e.g. control.lisp broadcasting to /ws/control) pushes a function
;; #'(lambda (label) ...) here. reload-handler fans out after a
;; successful reload. Keeping the list here (not in control.lisp)
;; avoids a cycle: the reload layer owns the event, subscribers attach
;; themselves.
(defvar *reload-observers* '())

(defun notify-reload-observers (label)
  "Call every function in *reload-observers* with LABEL. Individual
   observer failures are logged and swallowed so one broken observer
   cannot poison the others."
  (dolist (fn *reload-observers*)
    (handler-case (funcall fn label)
      (error (e)
        (format *error-output* "reload-observer-err: ~a~%" e)
        (finish-output *error-output*)))))

(defun %src-path (key)
  "Pathname to src/<key>.lisp relative to the running image's cwd."
  (merge-pathnames
   (format nil "src/~a.lisp" (string-downcase (symbol-name key)))
   (uiop:getcwd)))

(defun reload-module (key)
  "Reload one source file by keyword (e.g. :presets → src/presets.lisp).
   Returns (:ok :module K :elapsed-ms N). Signals if KEY is not in
   *reloadable-modules* or if the file fails to compile/load."
  (let ((k (intern (string-upcase (string key)) :keyword)))
    (unless (member k *reloadable-modules*)
      (error "module ~a not in *reloadable-modules*" k))
    (let* ((path (%src-path k))
           (start (get-internal-real-time)))
      (unless (uiop:file-exists-p path)
        (error "source file not found: ~a" path))
      (load path)
      (let ((elapsed-ms
              (floor (* 1000 (/ (- (get-internal-real-time) start)
                                internal-time-units-per-second)))))
        (list :ok t :module k :elapsed-ms elapsed-ms)))))

(defun reload-all-modules ()
  "Reload every module in *reloadable-modules* in declared order.
   Returns (:ok :modules (...) :elapsed-ms N)."
  (let ((start (get-internal-real-time)))
    (dolist (k *reloadable-modules*)
      (reload-module k))
    (list :ok t
          :modules *reloadable-modules*
          :elapsed-ms (floor (* 1000 (/ (- (get-internal-real-time) start)
                                        internal-time-units-per-second))))))

(defun reload-handler (module-or-nil)
  "HTTP handler body for /api/reload?module=NAME (nil = all).
   After a successful reload, push a 'reload:<module>' frame to every
   /ws/control listener so browsers hot-swap without an F5."
  (handler-case
      (let* ((result (if (and module-or-nil (plusp (length module-or-nil)))
                         (reload-module module-or-nil)
                         (reload-all-modules)))
             (modules (getf result :modules))
             (mod     (getf result :module))
             (label   (cond
                        (mod     (format nil "~(~a~)" mod))
                        (modules "all")
                        (t       "all"))))
        (notify-reload-observers (format nil "reload:~a" label))
        (format nil
                "{\"ok\":true,\"elapsed_ms\":~a~a}"
                (getf result :elapsed-ms)
                (cond
                  (modules
                   (format nil ",\"modules\":[~{\"~(~a~)\"~^,~}]"
                           modules))
                  (mod
                   (format nil ",\"module\":\"~(~a~)\"" mod))
                  (t ""))))
    (error (e)
      (format nil "{\"ok\":false,\"error\":\"~a\"}"
              (%json-escape (princ-to-string e))))))

;; ---- HTTP handler --------------------------------------------------------

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