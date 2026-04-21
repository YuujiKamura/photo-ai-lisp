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

   Returns a JSON string as the response body.  Callers must set the HTTP
   status code themselves:
     503 when *demo-session-id* is nil
     200 otherwise (even if the CP returns a mock response)"
  (declare (ignore id))
  (if (null *demo-session-id*)
      "{\"error\":\"no demo session configured yet\"}"
      (let* ((client  (%cp-client-or-mock))
             (frame   (make-cp-input cmd :session-id *demo-session-id*))
             (resp    (send-cp-command client frame))
             (n-bytes (length frame)))
        (declare (ignore resp))
        (format nil "{\"ok\":true,\"session\":\"~a\",\"bytes\":~d}"
                (%json-escape *demo-session-id*)
                n-bytes))))

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
