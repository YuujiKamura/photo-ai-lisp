(in-package #:photo-ai-lisp)

;;; Issue #19 — T2.b: CP UI Bridge.
;;; Provides a POST handler that accepts form submissions from the case view
;;; and forwards the command text to the deckpilot CP via cp-input.
;;;
;;; The session id is resolved via *demo-session-id*, a defvar that T2.c will
;;; populate on boot. Until then the var is nil and all requests return 503.
;;;
;;; Issue #30 Phase 2 (G2.a) — STATUS broadcast:
;;;   Before the legacy CP dispatch ships an INPUT/SHOW/STATE/LIST frame, we
;;;   broadcast a `status` envelope over /ws/control so every connected UI
;;;   client can toggle an in-flight indicator.  A matching :idle (or :error)
;;;   status goes out once the reply arrives (or the request fails).  The
;;;   envelope reuses the G1.a 5-part shape and its content carries the
;;;   originating request's msg_id as `target_msg_id`, so future multi-command
;;;   UIs can show per-command state instead of a global busy flag.

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

;;; --- G2.a: status envelope + broadcast ---------------------------------

(defun %status-state-string (state)
  "Translate the :state keyword into its wire string.  Unknown keywords
   fall through as their downcased symbol-name, which keeps the envelope
   well-formed even if a future caller passes an exotic state."
  (cond
    ((eq state :processing) "processing")
    ((eq state :idle)       "idle")
    ((eq state :error)      "error")
    ((stringp state)        state)
    (t (string-downcase (symbol-name state)))))

(defun %status-mode-string (mode)
  "Translate the :mode keyword into its wire string.
   Mode 1 = Jupyter 5-part envelope (current UI), Mode 2 = legacy CP."
  (cond
    ((eq mode :1)   "1")
    ((eq mode :2)   "2")
    ((stringp mode) mode)
    ((integerp mode) (princ-to-string mode))
    (t "1")))

(defun build-status-envelope (&key msg-id state (mode :1) error-class session-id)
  "Return a JSON string: a 5-part envelope with header.msg_type=\"status\".

   Keywords:
     :msg-id       target request's msg_id (goes to content.target_msg_id).
                   May be NIL — callers that broadcast a session-wide status
                   without a specific request pass nil, and the field is
                   serialised as an empty string.
     :state        :processing | :idle | :error  (content.state string).
     :mode         :1 | :2     (content.mode string).
     :error-class  symbol or string — when STATE is :error, its lowercased
                   name lands in content.error_class for UI diagnostics.
     :session-id   envelope header.session. Defaults to *demo-session-id*
                   so the broadcast chains back to the originating request.

   The envelope's own header.msg_id is a fresh UUID (via %make-header);
   the target request's msg_id is carried in content.target_msg_id so
   clients can correlate status events with in-flight requests."
  (let* ((sess     (or session-id *demo-session-id* ""))
         (target   (or msg-id ""))
         (err-str  (cond
                     ((null error-class) nil)
                     ((stringp error-class) error-class)
                     ((symbolp error-class)
                      (string-downcase (symbol-name error-class)))
                     (t (princ-to-string error-class))))
         (content  (if err-str
                       (%json-object
                        "state"         (%status-state-string state)
                        "mode"          (%status-mode-string mode)
                        "target_msg_id" target
                        "error_class"   err-str)
                       (%json-object
                        "state"         (%status-state-string state)
                        "mode"          (%status-mode-string mode)
                        "target_msg_id" target))))
    (%write-json (%make-envelope "status" sess content))))

(defun broadcast-status (&key msg-id state (mode :1) error-class session-id)
  "Push a STATUS envelope to every connected /ws/control client.

   Returns the recipient count (an integer).  With zero subscribers the
   function is a no-op returning 0 — safe to call from unit tests that
   never start the acceptor.

   The actual send routes through control.lisp's control-broadcast; we
   look it up via FUNCALL so this file stays clean of a cross-file
   forward reference at load time (control.lisp is loaded later in the
   ASDF serial sequence)."
  (let ((text (build-status-envelope :msg-id       msg-id
                                     :state        state
                                     :mode         mode
                                     :error-class  error-class
                                     :session-id   session-id)))
    (if (fboundp 'control-broadcast)
        (funcall 'control-broadcast text)
        0)))

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
         (cond
           ((zerop recipients)
            "{\"error\":\"no /ws/shell client connected; open the iframe first\"}")
           (t
            ;; C1 (issue #29): record INPUT verb per docs/tier-3/usage-log-format.md
            ;; before returning success. IGNORE-ERRORS so a filesystem hiccup can't
            ;; 503 a request that already broadcast successfully.
            (ignore-errors
              (write-usage-log-event
               :verb    "INPUT"
               :session (or *demo-session-id* "demo")
               :bytes   (usage-log-utf8-byte-count cmd)))
            (format nil "{\"ok\":true,\"mode\":\"shell-broadcast\",\"session\":\"demo\",\"recipients\":~d,\"bytes\":~d}"
                    recipients (length text))))))
      ;; Mode 3 — legacy CP, no session configured.
      ((null *demo-session-id*)
       "{\"error\":\"no demo session configured yet\"}")
      ;; Mode 2 — legacy CP path (kept for backwards compat).
      ;;
      ;; G2.a: bracket the send with STATUS broadcasts so the UI can show
      ;; an in-flight indicator.  The target_msg_id carried in each status
      ;; is the msg_id of the frame we just built (extracted via the
      ;; header accessor defined in cp-client.lisp), which lets a future
      ;; multi-command UI key state per-request.  On error we emit
      ;; :error (with error_class) before propagating the condition.
      (t
       (let* ((client    (%cp-client-or-mock))
              (frame     (make-cp-input cmd :session-id *demo-session-id*))
              (target-id (%extract-outgoing-msg-id frame))
              (n-bytes   (length frame)))
         (broadcast-status :msg-id     target-id
                           :state      :processing
                           :mode       :1
                           :session-id *demo-session-id*)
         (handler-case
             (let ((resp (send-cp-command client frame)))
               (declare (ignore resp))
               (broadcast-status :msg-id     target-id
                                 :state      :idle
                                 :mode       :1
                                 :session-id *demo-session-id*)
               (format nil "{\"ok\":true,\"session\":\"~a\",\"bytes\":~d}"
                       (%json-escape *demo-session-id*)
                       n-bytes))
           (error (c)
             (broadcast-status :msg-id      target-id
                               :state       :error
                               :mode        :1
                               :error-class (type-of c)
                               :session-id  *demo-session-id*)
             (error c))))))))

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
