;;;; scripts/inject-demo.lisp
;;;; Connect to /ws/shell as a WebSocket client and inject a sentinel
;;;; so the running browser reflects it and /api/shell-trace fills up.
;;;; Usage: sbcl --script scripts/inject-demo.lisp

(load "~/quicklisp/setup.lisp")
(ql:quickload :websocket-driver :silent t)

(defvar *done* nil)

(let ((client (wsd:make-client "ws://127.0.0.1:8090/ws/shell")))
  (wsd:on :open client
          (lambda ()
            (format t "CLIENT: connected~%")
            (finish-output)
            (wsd:send client (format nil "echo HELLO-FROM-LISP-CLIENT-~a~c"
                                     (random 10000) #\Return))
            (sleep 1.5)
            (wsd:close-connection client)))
  (wsd:on :message client
          (lambda (msg)
            (format t "CLIENT RECV: ~a~%" msg)
            (finish-output)))
  (wsd:on :close client
          (lambda (&key code reason)
            (declare (ignore code reason))
            (format t "CLIENT: disconnected~%")
            (finish-output)
            (setf *done* t)))
  (wsd:start-connection client)
  (loop until *done* do (sleep 0.1)))

(uiop:quit 0)
