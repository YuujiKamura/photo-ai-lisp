;;;; scripts/boot-hub.lisp
;;;; T1.c — boot-hub smoke: connect, LIST, disconnect, exit 0.
;;;; T2.c — boot-hub demo mode: start hub + spawn one sonnet session
;;;;         via deckpilot, then loop forever.
;;;;
;;;; Usage:
;;;;   sbcl --script scripts/boot-hub.lisp            ; T1.c smoke (CI)
;;;;   sbcl --script scripts/boot-hub.lisp --demo     ; T2.c demo mode
;;;;
;;;; Exit 0 on success, 1 on any error.

;;; GCA-1: Derive repo-root from *load-pathname* so the script works when
;;; invoked from any directory via `sbcl --script /path/to/scripts/boot-hub.lisp`.
;;; *load-pathname* is a standard CL variable — no package prefix needed before
;;; quicklisp is loaded.
(defvar *repo-root*
  (make-pathname :name nil :type nil :version nil
                 :defaults (merge-pathnames
                             (make-pathname :directory '(:relative :up))
                             (make-pathname :name nil :type nil :version nil
                                            :defaults (or *load-pathname* *default-pathname-defaults*)))))

(load "~/quicklisp/setup.lisp")
(push *repo-root* asdf:*central-registry*)
(ql:quickload :photo-ai-lisp :silent t)

(in-package #:photo-ai-lisp)

;;; GCA-2 helper: poll ready-state up to 2 s for :open.
(defun %wait-ws-open (driver &key (max-tries 20) (interval 0.1))
  "Return T when DRIVER's ready-state becomes :open, NIL on timeout."
  (loop repeat max-tries
        for state = (wsd:ready-state driver)
        when (eq state :open) return t
        do (sleep interval)
        finally (return nil)))

;;; ---- T2.c helpers ---------------------------------------------------------

(defun spawn-demo-agent (&key cwd)
  "Launch one sonnet session via deckpilot and store the session id.

   Runs: deckpilot launch sonnet \"hub ready, awaiting first input\" --cwd <cwd>
   Captures stdout, extracts the session name via parse-demo-session-name,
   and sets *demo-session-id*.  Calls uiop:quit 1 on failure."
  (let* ((cwd-path (or cwd (namestring *repo-root*)))
         (argv     (list "deckpilot" "launch" "sonnet"
                         "hub ready, awaiting first input"
                         "--cwd" cwd-path))
         (output   (handler-case
                       (uiop:run-program argv
                                         :output :string
                                         :error-output nil
                                         :ignore-error-status t)
                     (error (e)
                       (format *error-output*
                               "[DEMO] deckpilot exec error: ~A~%" e)
                       (uiop:quit 1))))
         (session  (parse-demo-session-name output)))
    (unless session
      (format *error-output*
              "[DEMO] FATAL: could not parse session name from deckpilot output: ~S~%"
              output)
      (uiop:quit 1))
    (setf *demo-session-id* session)
    (format t "[DEMO] spawned ~A~%" session)))

;;; ---- argument dispatch ----------------------------------------------------

(defun demo-mode-p ()
  "Return T when --demo is present in the POSIX argv."
  (member "--demo" sb-ext:*posix-argv* :test #'string=))

;;; ---- T1.c smoke (default, no args) ----------------------------------------

(defun run-smoke ()
  (handler-case
      (progn
        (format t "[BOOT] photo-ai-lisp hub smoke start~%")
        (let* ((client (connect-cp :port 8080))
               (driver (cp-client-driver client))
               (ready (and driver (%wait-ws-open driver))))
          ;; GCA-2: check actual WebSocket handshake, not just object creation.
          (unless ready
            (let ((state (and driver (wsd:ready-state driver))))
              (format *error-output* "[BOOT] CONNECT: FAIL (ready-state=~A)~%" state)
              (uiop:quit 1)))
          (format t "[BOOT] connect ws://127.0.0.1:8080/ws -> OK~%")

          ;; GCA-2: wrap blocking send-cp-command in a timeout to avoid hang.
          (let ((resp (bt:with-timeout (5)
                        (send-cp-command client (make-cp-list-tabs)))))
            (unless (getf resp :ok)
              (error "LIST returned non-ok: ~S" resp))
            (format t "[BOOT] LIST ok=T session-count=~A~%"
                    (length (getf resp :data))))
          (ignore-errors (disconnect-cp client)))
        (format t "[BOOT] ok~%")
        (uiop:quit 0))
    (bt:timeout ()
      (format *error-output* "[BOOT] FATAL: send-cp-command timed out after 5 s~%")
      (uiop:quit 1))
    (error (c)
      (format *error-output* "[BOOT] FATAL: ~A~%" c)
      (uiop:quit 1))))

;;; ---- T2.c demo mode (--demo flag) -----------------------------------------

(defun run-demo ()
  (handler-case
      (progn
        ;; photo-ai-lisp already loaded at top; re-quickload is a no-op but kept
        ;; here as a guard in case demo is invoked standalone in future.
        (ql:quickload :photo-ai-lisp :silent t)
        (start :port 8090)
        (format t "[HUB] started on :8090~%")
        (spawn-demo-agent :cwd (namestring *repo-root*))
        (format t "[DEMO] session=~A~%" *demo-session-id*)
        ;; Keep image alive so REPL (e.g. swank/sly) can inspect the var.
        (loop (sleep 60)))
    (error (c)
      (format *error-output* "[DEMO] FATAL: ~A~%" c)
      (uiop:quit 1))))

;;; ---- Entry point ----------------------------------------------------------

(if (demo-mode-p)
    (run-demo)
    (run-smoke))
