(load "~/quicklisp/setup.lisp")
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :photo-ai-lisp :silent t)

(in-package #:photo-ai-lisp)

(format t "--- Initializing photo-ai-lisp Hub ---~%")

;; Step 1: Connect to Deckpilot
(defvar *cp-client* (connect-cp :port 8080))
(format t "Connected to Deckpilot at ws://localhost:8080/ws~%")

;; Step 2: Set ghostty-28900 as the Hub worker
(defvar *hub-session* "ghostty-28900")
(format t "Hub role assigned to session: ~A~%" *hub-session*)

;; Step 3: Test connectivity by sending a 'PING' style command (STATE)
(let ((resp (send-cp-command *cp-client* (make-cp-state *hub-session*))))
  (format t "Worker STATE response: ~S~%" resp))

;; Step 4: Finalize Hub state
(format t "Hub is now READY. Waiting for Pipeline instructions...~%")

;; Keep REPL alive or start server if needed
;; (photo-ai-lisp:start)
