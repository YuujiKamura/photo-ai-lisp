(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT5 — coverage for src/term.lisp (Issue #17 CP Integration)
;;; Old process management tests (UT5a, UT5c, UT5e, UT5f, UT5h) are REMOVED
;;; as the Lisp side no longer spawns shell processes directly.

;;; -----------------------------------------------------------------------
;;; UT5b — shell-client class and basic accessors.
(test term-shell-client-class-defined
  (is-true (find-class 'photo-ai-lisp::shell-client nil)
           "shell-client class should be defined"))

(test term-shell-client-accessors-defaults
  (let ((c (make-instance 'photo-ai-lisp::shell-client)))
    (is (null (photo-ai-lisp::shell-client-cp-client c))
        "shell-client-cp-client should default to nil")
    ;; setf round-trip.
    (setf (photo-ai-lisp::shell-client-cp-client c) :mock-cp)
    (is (eq :mock-cp (photo-ai-lisp::shell-client-cp-client c))
        "shell-client-cp-client accessor should round-trip via setf")))

;;; -----------------------------------------------------------------------
;;; UT5d — text-message-received (echo-resource) echoes verbatim.
;;; Kept as a basic sanity test for WebSocket message dispatch.

(defvar *sent-messages* nil)

(test term-echo-resource-text-message-echoes
  (let ((*sent-messages* nil)
        (%real-send (symbol-function 'hunchensocket:send-text-message)))
    (unwind-protect
         (progn
           (setf (symbol-function 'hunchensocket:send-text-message)
                 (lambda (c m) (push (cons c m) *sent-messages*)))
           (let ((client (make-instance 'hunchensocket:websocket-client
                                        'hunchensocket::input-stream (make-broadcast-stream)
                                        'hunchensocket::output-stream (make-broadcast-stream)
                                        'hunchensocket::request :mock-request)))
             (hunchensocket:text-message-received
              photo-ai-lisp::*echo-resource* client "ping-123")
             (is (equal (list (cons client "ping-123")) *sent-messages*))))
      (setf (symbol-function 'hunchensocket:send-text-message) %real-send))))

;;; -----------------------------------------------------------------------
;;; UT5g — CP Bridge placeholders.
(test term-shell-resource-cp-bridge-spec
  (skip "CP Bridge forwarding to /cp will be implemented in Atom 17.5"))
