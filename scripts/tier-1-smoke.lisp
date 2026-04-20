(load "~/quicklisp/setup.lisp")
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :photo-ai-lisp :silent t)

(in-package #:photo-ai-lisp)

(handler-case
    (progn
      (format t "--- TIER 1 SMOKE START ---~%")
      (let ((client (connect-cp :port 8080)))
        (format t "CONNECT OK: ~A~%" (if client "YES" "NO"))

        ;; 1. LIST
        (format t "SENDING LIST...~%")
        (let ((resp (send-cp-command client (make-cp-list-tabs))))
          (format t "LIST resp: ~S~%" resp)
          (format t "OK field: ~A~%" (getf resp :ok)))

        ;; 2. STATE on a known session
        (let* ((target-session "ghostty-17676")
               (resp (send-cp-command client (make-cp-state target-session))))
          (format t "STATE(~A) resp: ~S~%" target-session resp)
          (format t "STATUS field: ~A~%" (getf resp :status)))

        ;; 3. wait-for-completion on nonexistent
        (format t "TESTING wait-for-completion on nonexistent...~%")
        (let ((result (wait-for-completion client "nonexistent" :timeout 2 :interval 1)))
          (format t "wait-for-completion(nonexistent) result: ~S~%" result))

        (disconnect-cp client)
        (format t "--- TIER 1 SMOKE END ---~%")))
  (error (c)
    (format *error-output* "ERROR: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit 0)
