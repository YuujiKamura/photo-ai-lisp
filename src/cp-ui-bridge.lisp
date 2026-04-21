(in-package #:photo-ai-lisp)

;;; Issue #19 — T2.b: CP UI Bridge.
;;; Provides a POST handler that accepts form submissions from the case view
;;; and forwards the command text to the deckpilot CP via cp-input.
;;;
;;; The session id is resolved via *demo-session-id*, a defvar that T2.c will
;;; populate on boot. Until then the var is nil and all requests return 503.

(defvar *demo-session-id* nil
  "Session id of the fixed demo agent session managed by boot-hub.
   Nil until T2.c boot-hub spawn sets it.  When nil, the input-bridge
   returns HTTP 503 rather than attempt a blind send.")

(defvar *demo-cp-client* nil
  "CP client connected to the demo hub.  Nil until T2.c wires it.
   The input-bridge uses :mock-client as a fallback so unit tests stay
   synchronous without a live WebSocket.")

(defun %cp-client-or-mock ()
  "Return *demo-cp-client* when set, else :mock-client for offline tests."
  (or *demo-cp-client* :mock-client))

(defun input-bridge-handler (id cmd)
  "Handle POST /cases/:id/input.

   ID  — case id string from the URL (informational; not used for routing).
   CMD — command text from the 'cmd' form field.

   Returns a JSON string as the response body.  The HTTP status code is
   set by the dispatcher wrapper in src/main.lisp based on whether the
   body contains the \"error\" key.

   T2.h pivot — three execution modes:

     1. Demo mode (PHOTO_AI_LISP_DEMO_AGENT env var set): broadcast CMD
        directly to every connected /ws/shell child via
        shell-broadcast-input. The iframe-visible child IS the agent,
        so INPUT lands in its stdin and its output streams back over
        the same WebSocket. When no /ws/shell is connected (recipients
        = 0), return an error body so the dispatcher can 503.

     2. Legacy CP mode with *demo-session-id* set: preserved path
        through send-cp-command (uses :mock-client when no live CP
        client is wired). Not used by the current pivoted demo but
        kept so downstream callers that poke *demo-session-id*
        directly keep working.

     3. Legacy CP mode with *demo-session-id* nil: error body."
  (declare (ignore id))
  (let ((agent (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")))
    (cond
      ;; Mode 1 — demo mode: shell-broadcast to /ws/shell children.
      ((and agent (plusp (length agent)))
       (let* ((text       (format nil "~A~%" cmd))
              (recipients (shell-broadcast-input text)))
         (if (zerop recipients)
             "{\"error\":\"no /ws/shell client connected; open the iframe first\"}"
             (format nil "{\"ok\":true,\"mode\":\"shell-broadcast\",\"session\":\"demo\",\"recipients\":~d,\"bytes\":~d}"
                     recipients (length text)))))
      ;; Mode 3 — legacy CP, no session configured.
      ((null *demo-session-id*)
       "{\"error\":\"no demo session configured yet\"}")
      ;; Mode 2 — legacy CP path (kept for backwards compat).
      (t
       (let* ((client  (%cp-client-or-mock))
              (frame   (make-cp-input cmd :session-id *demo-session-id*))
              (resp    (send-cp-command client frame))
              (n-bytes (length frame)))
         (declare (ignore resp))
         (format nil "{\"ok\":true,\"session\":\"~a\",\"bytes\":~d}"
                 (%json-escape *demo-session-id*)
                 n-bytes))))))

;;; T2.c — parse-demo-session-name
;;; Pure function: given the stdout string from `deckpilot launch`, extract
;;; the session name (last non-empty line).  Returns nil on bad input so
;;; callers can decide how to fail rather than propagating an error.

(defun parse-demo-session-name (s)
  "Extract the session name from DECKPILOT LAUNCH stdout string S.

   Strategy:
     1. Split S on newlines.
     2. Take the last non-empty (after trim) token.
     3. If that token starts with \"ghostty-\" return it, else return NIL.
   NIL is also returned for NIL input or blank strings."
  (when (and s (plusp (length s)))
    (let* ((lines  (uiop:split-string s :separator '(#\Newline #\Return)))
           (trimmed (remove-if (lambda (l) (zerop (length (string-trim " " l)))) lines))
           (last-line (and trimmed (string-trim " " (car (last trimmed))))))
      (when (and last-line
                 (> (length last-line) 8)
                 (string= "ghostty-" (subseq last-line 0 8)))
        last-line))))
