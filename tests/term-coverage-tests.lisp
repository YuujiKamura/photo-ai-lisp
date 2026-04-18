(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT5 — coverage gap-fill for src/term.lisp
;;; Covers:
;;;   %shell-argv, %stdout-pump,
;;;   shell-client class + accessors,
;;;   text-message-received (echo-resource) via captured-send mock,
;;;   text-message-received (shell-resource) no-op with nil child,
;;;   client-disconnected (shell-resource) no-op with nil child.
;;;
;;; client-connected (shell-resource) is NOT tested here because it spawns
;;; a real child shell and a bordeaux-thread; see skip-with-reason below.

;;; -----------------------------------------------------------------------
;;; UT5a — %shell-argv dispatches on OS.
(test term-shell-argv-platform
  (let ((argv (photo-ai-lisp::%shell-argv)))
    (is-true (listp argv)
             "%shell-argv should return a list, got: ~s" argv)
    (is-true (stringp (first argv))
             "first element of %shell-argv should be a string, got: ~s"
             (first argv))
    (if (uiop:os-windows-p)
        (progn
          (is (string= "cmd.exe" (first argv))
              "Windows %shell-argv should start with cmd.exe, got: ~s" argv)
          (is (= 1 (length argv))
              "Windows %shell-argv should have exactly one element, got: ~s" argv))
        (progn
          (is (string= "/bin/bash" (first argv))
              "Unix %shell-argv should start with /bin/bash, got: ~s" argv)
          (is (equal '("/bin/bash" "--norc" "--noprofile") argv)
              "Unix %shell-argv should be bash with --norc --noprofile, got: ~s"
              argv)))))

;;; -----------------------------------------------------------------------
;;; UT5b — shell-client class and accessors exist and default to nil.
(test term-shell-client-class-defined
  (is-true (find-class 'photo-ai-lisp::shell-client nil)
           "shell-client class should be defined"))

(test term-shell-client-accessors-defaults
  (let ((c (%make-shell-client-for-test)))
    (is (null (photo-ai-lisp::shell-client-child c))
        "shell-client-child should default to nil")
    (is (null (photo-ai-lisp::shell-client-reader-thread c))
        "shell-client-reader-thread should default to nil")
    ;; setf round-trip.
    (setf (photo-ai-lisp::shell-client-child c) :sentinel)
    (is (eq :sentinel (photo-ai-lisp::shell-client-child c))
        "shell-client-child accessor should round-trip via setf")
    (setf (photo-ai-lisp::shell-client-reader-thread c) :thread-sentinel)
    (is (eq :thread-sentinel (photo-ai-lisp::shell-client-reader-thread c))
        "shell-client-reader-thread accessor should round-trip via setf")))

;;; -----------------------------------------------------------------------
;;; UT5c — %stdout-pump flushes buffered characters to the client and
;;; returns when the child reports not alive and stdout drains to EOF.
;;;
;;; We construct a fake child-process whose stdout is a string-input-stream
;;; wrapping a short payload, and whose `process' slot is nil so that
;;; child-alive-p raises an error — which is caught by the handler-case
;;; inside %stdout-pump, causing it to return.  Before that happens, the
;;; pump buffers the payload characters and (on the empty-listen branch)
;;; sends them via hunchensocket:send-text-message.  We stub that generic
;;; with a :around method keyed on our fake-client class.

;; hunchensocket:send-text-message is an ordinary (non-generic) function,
;; so we cannot specialize it via defmethod.  Instead we dynamically swap
;; its symbol-function for the scope of a single test using
;; WITH-STUBBED-SEND, capturing (client . msg) pairs into *SENT-MESSAGES*.
(defvar *sent-messages* nil
  "Captured (client . message) pairs from the stubbed send-text-message.")

;; Build a shell-client without a real WebSocket; hunchensocket's
;; websocket-client demands non-nil input/output streams and a request,
;; but never exercises them in the paths we test (the (when child ...)
;; guards short-circuit before any stream is touched).
(defun %make-shell-client-for-test ()
  (make-instance 'photo-ai-lisp::shell-client
                 'hunchensocket::input-stream  (make-broadcast-stream)
                 'hunchensocket::output-stream (make-broadcast-stream)
                 'hunchensocket::request       :mock-request))

(defmacro with-stubbed-send (&body body)
  `(let ((*sent-messages* nil)
         (%real-send (symbol-function 'hunchensocket:send-text-message)))
     (unwind-protect
         (progn
           (setf (symbol-function 'hunchensocket:send-text-message)
                 (lambda (c m)
                   (push (cons c m) *sent-messages*)))
           ,@body)
       (setf (symbol-function 'hunchensocket:send-text-message) %real-send))))

(test term-stdout-pump-flushes-and-exits
  (with-stubbed-send
    (let* ((payload "hello-pump")
           (in (make-string-input-stream payload))
           ;; child with nil process slot → child-alive-p will signal an error
           ;; inside %stdout-pump, which is caught by its handler-case and
           ;; causes the pump to return normally.
           (child (photo-ai-lisp::make-child-process
                   :process nil :stdin nil :stdout in))
           (client (cons :fake-client :ignored)))
      (finishes (photo-ai-lisp::%stdout-pump client child))
      (let ((all (apply #'concatenate 'string
                        (mapcar #'cdr (reverse *sent-messages*)))))
        (is (search "hello-pump" all)
            "%stdout-pump should have sent 'hello-pump' to client, got: ~s"
            *sent-messages*)))))

;;; -----------------------------------------------------------------------
;;; UT5d — text-message-received (echo-resource) echoes verbatim.

;; hunchensocket:text-message-received is a generic function; our defmethod
;; dispatches on echo-resource and a websocket-client specializer.  We must
;; construct a real websocket-client (not a cons), but its streams are never
;; touched because the echo method only calls send-text-message (stubbed).
(test term-echo-resource-text-message-echoes
  (with-stubbed-send
    (let ((client (make-instance 'hunchensocket:websocket-client
                                 'hunchensocket::input-stream
                                 (make-broadcast-stream)
                                 'hunchensocket::output-stream
                                 (make-broadcast-stream)
                                 'hunchensocket::request :mock-request)))
      (hunchensocket:text-message-received
       photo-ai-lisp::*echo-resource* client "ping-123")
      (is (equal (list (cons client "ping-123")) *sent-messages*)
          "echo-resource text-message-received should echo message verbatim, got: ~s"
          *sent-messages*))))

;;; -----------------------------------------------------------------------
;;; UT5e — text-message-received (shell-resource) with nil child is a no-op.
;;; This exercises the (when child ...) guard.

(test term-shell-resource-text-message-no-child-noop
  (let ((client (%make-shell-client-for-test)))
    (setf (photo-ai-lisp::shell-client-child client) nil)
    (finishes
     (hunchensocket:text-message-received
      photo-ai-lisp::*shell-resource* client "ignored"))))

;;; -----------------------------------------------------------------------
;;; UT5f — client-disconnected (shell-resource) with nil child is a no-op.
(test term-shell-resource-client-disconnected-no-child-noop
  (let ((client (%make-shell-client-for-test)))
    (setf (photo-ai-lisp::shell-client-child client) nil)
    (finishes
     (hunchensocket:client-disconnected
      photo-ai-lisp::*shell-resource* client))
    (is (null (photo-ai-lisp::shell-client-child client))
        "client-disconnected should leave nil child untouched")))

;;; -----------------------------------------------------------------------
;;; UT5g — client-connected (shell-resource) is coverage-skipped because
;;; it spawns a real shell subprocess and a bordeaux-thread.  The behavior
;;; is exercised end-to-end by the /ws/shell integration path; the
;;; no-child code paths (2b/2d) are covered by UT5e/UT5f above.
(test term-shell-resource-client-connected-skipped
  (skip "client-connected spawns a real shell subprocess + thread; \
exercised via the WebSocket integration path, not unit-testable in isolation."))

;;; -----------------------------------------------------------------------
;;; UT5h — make-child-process constructor (defstruct-generated) smoke test.
;;; Already implicitly covered by spawn-child in proc tests, but we assert
;;; the constructor returns a child-process with slots preserved.
(test term-make-child-process-constructor
  (let ((c (photo-ai-lisp::make-child-process
            :process :p :stdin :si :stdout :so)))
    (is (typep c 'photo-ai-lisp::child-process)
        "make-child-process should return a child-process")
    (is (eq :p  (photo-ai-lisp::child-process-process c)))
    (is (eq :si (photo-ai-lisp::child-process-stdin  c)))
    (is (eq :so (photo-ai-lisp::child-process-stdout c)))))
