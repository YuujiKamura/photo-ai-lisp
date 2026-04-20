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
