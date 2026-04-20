;;;; scripts/boot-hub.lisp
;;;; T1.c — boot-hub smoke: connect, LIST, disconnect, exit 0.
;;;;
;;;; Usage:
;;;;   sbcl --script scripts/boot-hub.lisp
;;;;
;;;; Exit 0 on success, 1 on any error.

(load "~/quicklisp/setup.lisp")
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :photo-ai-lisp :silent t)

(in-package #:photo-ai-lisp)

(handler-case
    (progn
      (format t "[BOOT] photo-ai-lisp hub smoke start~%")
      (let ((client (connect-cp :port 8080)))
        (format t "[BOOT] connect ws://127.0.0.1:8080/ws -> ~A~%"
                (if client "OK" "NIL"))
        (let ((resp (send-cp-command client (make-cp-list-tabs))))
          (unless (getf resp :ok)
            (error "LIST returned non-ok: ~S" resp))
          (format t "[BOOT] LIST ok=T session-count=~A~%"
                  (length (getf resp :data))))
        (ignore-errors (disconnect-cp client)))
      (format t "[BOOT] ok~%")
      (uiop:quit 0))
  (error (c)
    (format *error-output* "[BOOT] FATAL: ~A~%" c)
    (uiop:quit 1)))
