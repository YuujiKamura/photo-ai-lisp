;;;; scripts/cp-smoke.lisp
;;;; T1.b — CP round-trip smoke: LIST / STATE / INPUT / SHOW against a live session.
;;;;
;;;; Usage:
;;;;   sbcl --script scripts/cp-smoke.lisp [session-name]
;;;;
;;;; If session-name is omitted, *target-session* below is used.
;;;; Exit 0 on all-4-ok, 1 on any non-ok / error.

(load "~/quicklisp/setup.lisp")
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :photo-ai-lisp :silent t)

(in-package #:photo-ai-lisp)

(defparameter *target-session* "ghostty-30028"
  "deckpilot session name used as the INPUT/STATE/SHOW target.
   Override by passing session-name as the first script arg.")

(defvar *failure-count* 0)

(defun %ok? (resp)
  (and (listp resp) (getf resp :ok)))

(defun %log-verb (verb resp)
  (let ((ok (%ok? resp)))
    (format t "[~A] ok=~A resp=~S~%" verb (if ok "T" "NIL") resp)
    (unless ok (incf *failure-count*))
    ok))

(let ((args (or #+sbcl (rest sb-ext:*posix-argv*) nil)))
  (when (and args (first args))
    (setf *target-session* (first args))))

(handler-case
    (progn
      (format t "--- T1.b CP SMOKE START ---~%")
      (format t "target-session: ~A~%" *target-session*)
      (let ((client (connect-cp :port 8080)))
        (format t "CONNECT: ~A~%" (if client "OK" "NIL"))

        ;; 1. LIST
        (format t "~%>>> LIST~%")
        (%log-verb "LIST" (send-cp-command client (make-cp-list-tabs)))

        ;; 2. STATE against the live session
        (format t "~%>>> STATE ~A~%" *target-session*)
        (%log-verb "STATE" (send-cp-command client (make-cp-state *target-session*)))

        ;; 3. INPUT — send a harmless shell command to the live session
        (format t "~%>>> INPUT echo t1b-ping -> ~A~%" *target-session*)
        (%log-verb "INPUT"
                   (send-cp-command client
                                    (make-cp-input "echo t1b-ping"
                                                   :session-id *target-session*)))

        ;; Give the child shell a moment to render the echo.
        (sleep 1)

        ;; 4. SHOW — read the tail of the session buffer
        (format t "~%>>> SHOW tail n=5 <- ~A~%" *target-session*)
        (%log-verb "SHOW"
                   (send-cp-command client
                                    (make-cp-tail :n 5
                                                  :session-id *target-session*)))

        ;; Swallow the benign "Cannot destroy thread" noise wsd emits on close.
        (ignore-errors (disconnect-cp client)))
      (format t "~%--- T1.b CP SMOKE END --- failures=~D~%" *failure-count*)
      (if (zerop *failure-count*)
          (uiop:quit 0)
          (uiop:quit 1)))
  (error (c)
    (format *error-output* "FATAL: ~A~%" c)
    (uiop:quit 2)))
