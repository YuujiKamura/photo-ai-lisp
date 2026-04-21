;;;; scripts/cp-smoke.lisp
;;;; T1.b — CP round-trip smoke: LIST / STATE / INPUT / SHOW against a live session.
;;;;
;;;; Usage:
;;;;   sbcl --script scripts/cp-smoke.lisp [session-name]
;;;;
;;;; If session-name is omitted, the first idle (or any live) session returned
;;;; by LIST is used automatically.
;;;; Exit 0 on all-4-ok, 1 on any non-ok / error.

;;; GCA-1: Derive repo-root from *load-pathname* so the script works when
;;; invoked from any directory via `sbcl --script /path/to/scripts/cp-smoke.lisp`.
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

;;; CX-2: *target-session* starts NIL; resolved dynamically after LIST.
(defparameter *target-session* nil
  "deckpilot session name used as the INPUT/STATE/SHOW target.
   When NIL (the default), the first idle session from LIST is used automatically.
   Override by passing session-name as the first script arg.")

(defvar *failure-count* 0)

(defun %ok? (resp)
  (and (listp resp) (getf resp :ok)))

;;; CX-1: wrap every send-cp-command call in a 5-second timeout.
(defmacro %timed-send (client cmd-form)
  "Send CMD-FORM with a 5-second timeout. Signals bt:timeout if no reply."
  `(bt:with-timeout (5)
     (send-cp-command ,client ,cmd-form)))

(defun %log-verb (verb resp)
  (let ((ok (%ok? resp)))
    (format t "[~A] ok=~A resp=~S~%" verb (if ok "T" "NIL") resp)
    (unless ok (incf *failure-count*))
    ok))

;;; GCA-3 helper: poll ready-state up to 2 s for :open.
(defun %wait-ws-open (driver &key (max-tries 20) (interval 0.1))
  "Return T when DRIVER's ready-state becomes :open, NIL on timeout."
  (loop repeat max-tries
        for state = (wsd:ready-state driver)
        when (eq state :open) return t
        do (sleep interval)
        finally (return nil)))

;;; CX-2: Pick the first idle session from LIST response.
;;; :data is a vector of hash-tables (shasht JSON array), each with
;;; string keys "name" and "status".
;;; Falls back to first live session of any status if none is idle.
(defun %pick-session (list-resp)
  (let ((sessions (getf list-resp :data)))
    (when (and sessions (plusp (length sessions)))
      (or (find "idle" sessions :key (lambda (s) (gethash "status" s ""))
                                :test #'string=)
          (aref sessions 0)))))

(let ((args (or #+sbcl (rest sb-ext:*posix-argv*) nil)))
  (when (and args (first args))
    (setf *target-session* (first args))))

(handler-case
    (progn
      (format t "--- T1.b CP SMOKE START ---~%")
      (let* ((client (connect-cp :port 8080))
             (driver (cp-client-driver client))
             ;; GCA-3: verify actual WebSocket handshake.
             (ready (and driver (%wait-ws-open driver))))
        (unless ready
          (let ((state (and driver (wsd:ready-state driver))))
            (format *error-output* "CONNECT: FAIL (ready-state=~A)~%" state)
            (uiop:quit 1)))
        (format t "CONNECT: OK~%")

        ;; 1. LIST — also used to resolve *target-session* when not supplied.
        (format t "~%>>> LIST~%")
        (let* ((list-resp (%timed-send client (make-cp-list-tabs)))
               (ok (%log-verb "LIST" list-resp)))
          ;; CX-2: resolve target session from LIST result when no arg given.
          (when (and ok (null *target-session*))
            (let ((session (%pick-session list-resp)))
              (if session
                  (setf *target-session* (gethash "name" session))
                  (progn
                    (format *error-output*
                            "FATAL: no live sessions returned by LIST — nothing to test against~%")
                    (uiop:quit 1))))))

        (format t "target-session: ~A~%" *target-session*)

        ;; 2. STATE against the live session
        (format t "~%>>> STATE ~A~%" *target-session*)
        (%log-verb "STATE" (%timed-send client (make-cp-state *target-session*)))

        ;; 3. INPUT — send a harmless shell command to the live session
        (format t "~%>>> INPUT echo t1b-ping -> ~A~%" *target-session*)
        (%log-verb "INPUT"
                   (%timed-send client
                                (make-cp-input "echo t1b-ping"
                                               :session-id *target-session*)))

        ;; Give the child shell a moment to render the echo.
        (sleep 1)

        ;; 4. SHOW — read the tail of the session buffer
        (format t "~%>>> SHOW tail n=5 <- ~A~%" *target-session*)
        (%log-verb "SHOW"
                   (%timed-send client
                                (make-cp-tail :n 5
                                              :session-id *target-session*)))

        ;; Swallow the benign "Cannot destroy thread" noise wsd emits on close.
        (ignore-errors (disconnect-cp client)))
      (format t "~%--- T1.b CP SMOKE END --- failures=~D~%" *failure-count*)
      (if (zerop *failure-count*)
          (uiop:quit 0)
          (uiop:quit 1)))
  (bt:timeout ()
    (format *error-output* "FATAL: send-cp-command timed out after 5 s~%")
    (uiop:quit 1))
  (error (c)
    (format *error-output* "FATAL: ~A~%" c)
    (uiop:quit 2)))
