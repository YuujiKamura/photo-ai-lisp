(in-package #:photo-ai-lisp)

;;; Issue #17 / #30 — CP (Control Plane) Protocol implementation.
;;;
;;; Phase 1 (G1.a): 5-part envelope compliant with the Jupyter messaging
;;; spec skeleton. Every client-originated message has the shape:
;;;
;;;   { "header":        { msg_id, session, username, date, msg_type, version },
;;;     "parent_header": {},
;;;     "metadata":      {},
;;;     "content":       { <existing flat payload for wire-compat> },
;;;     "buffers":       [] }
;;;
;;; The `content` object keeps the current flat payload fields
;;; (cmd/from/msg/session etc.) for wire compatibility with deckpilot until
;;; Team delta's G1.c negotiation. This deliberately duplicates info with the
;;; header and is a migration shim, not the final shape.
;;;
;;; HMAC signing is out of scope for G1.a (no `signature` field).
;;;
;;; `cp-parse-response` accepts both the new 5-part envelope and the legacy
;;; flat JSON {"cmd":..., "ok":..., ...} envelope. In both cases it returns
;;; a plist with (at minimum) the keys
;;;    :cmd :ok :error :data :status :mode :message :msg-type :session :content
;;; so existing callers that destructure :ok/:status/etc. continue to work
;;; unchanged.

(defun %encode-base64 (string)
  "Encodes STRING to base64 using cl-base64.
   ghostty-web expects standard base64 for INPUT/PASTE."
  (uiop:symbol-call '#:cl-base64 '#:string-to-base64-string string))

(defun %iso8601-utc-now ()
  "Return an ISO-8601 UTC timestamp string with sub-second precision and Z suffix.
   Example: 2026-04-21T03:02:56.133759Z"
  (local-time:format-rfc3339-timestring
   nil
   (local-time:now)
   :timezone local-time:+utc-zone+))

(defun %make-uuid-string ()
  "Return a fresh UUIDv4 as a canonical 36-char string."
  (format nil "~A" (uuid:make-v4-uuid)))

(defun %json-object (&rest key-value-pairs)
  "Build a hash-table shasht will serialise as a JSON object.
   Example: (%json-object \"a\" 1 \"b\" \"x\") -> {\"a\":1,\"b\":\"x\"}."
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on key-value-pairs by #'cddr
          do (setf (gethash k h) v))
    h))

(defun %empty-object ()
  "Return a hash table shasht serialises as an empty JSON object {}."
  (make-hash-table :test #'equal))

(defun %make-header (msg-type session-id)
  "Build the 5-part envelope header as a hash-table for MSG-TYPE and SESSION-ID.
   Every call mints a fresh msg_id and date."
  (%json-object
   "msg_id"   (%make-uuid-string)
   "session"  (or session-id "")
   "username" "photo-ai-lisp"
   "date"     (%iso8601-utc-now)
   "msg_type" msg-type
   "version"  "5.4"))

(defun %make-envelope (msg-type session-id content)
  "Assemble a full 5-part envelope hash-table ready for shasht serialisation.
   CONTENT is a hash-table describing the content object."
  (%json-object
   "header"        (%make-header msg-type session-id)
   "parent_header" (%empty-object)
   "metadata"      (%empty-object)
   "content"       content
   "buffers"       #()))

(defun %write-json (obj)
  "Serialise OBJ (hash-table-shaped) to a compact JSON string using shasht.
   We force *print-pretty* off so the output contains no whitespace between
   tokens — wire compatibility with deckpilot's parser (which accepts either
   shape) and stability for the existing substring-style tests."
  (let ((*print-pretty* nil))
    (shasht:write-json obj nil)))

(defun make-cp-input (text &key (from "photo-ai-lisp") session-id)
  "Generate an INPUT message in the 5-part envelope.
   TEXT is base64-encoded into content.msg for wire compatibility."
  (let* ((sess (or session-id ""))
         (content (%json-object
                   "cmd"     "INPUT"
                   "from"    from
                   "msg"     (%encode-base64 text)
                   "session" sess)))
    (%write-json (%make-envelope "INPUT" sess content))))

(defun make-cp-tail (&key (n 20) session-id)
  "Generate a SHOW (tail) message in the 5-part envelope."
  (let* ((sess (or session-id ""))
         (content (%json-object
                   "cmd"     "SHOW"
                   "mode"    "buffer"
                   "session" sess
                   "lines"   n)))
    (%write-json (%make-envelope "SHOW" sess content))))

(defun make-cp-state (&optional session-id)
  "Generate a STATE message in the 5-part envelope."
  (let* ((sess (or session-id ""))
         (content (%json-object
                   "cmd"     "STATE"
                   "session" sess)))
    (%write-json (%make-envelope "STATE" sess content))))

(defun make-cp-list-tabs ()
  "Generate a LIST message in the 5-part envelope."
  (let ((content (%json-object "cmd" "LIST")))
    (%write-json (%make-envelope "LIST" "" content))))

(defun %hash-get (hash key &optional default)
  "Safe gethash returning DEFAULT when HASH is not a hash table or KEY is absent."
  (if (hash-table-p hash)
      (multiple-value-bind (v present) (gethash key hash)
        (if present v default))
      default))

(defun %parse-5part (obj)
  "Parse an OBJ hash-table that has a \"header\" key as a 5-part envelope.
   Return a plist exposing :msg-type, :session, :content plus the legacy
   accessor keys synthesised from content so existing callers keep working."
  (let* ((header   (%hash-get obj "header"))
         (content  (%hash-get obj "content"))
         (msg-type (%hash-get header "msg_type"))
         (session  (%hash-get header "session")))
    (list :msg-type msg-type
          :session  session
          :content  content
          ;; Legacy accessor shim: pull the same well-known fields out of
          ;; content so code that reads :cmd/:ok/:status/... via getf still
          ;; works against 5-part envelopes produced by a future server.
          :cmd      (%hash-get content "cmd" msg-type)
          :ok       (%hash-get content "ok")
          :error    (%hash-get content "error")
          :data     (%hash-get content "data")
          :status   (%hash-get content "status")
          :mode     (%hash-get content "mode")
          :message  (%hash-get content "message"))))

(defun %parse-legacy-flat (obj)
  "Parse an OBJ hash-table that lacks a \"header\" key as the legacy flat
   envelope. Synthesise :msg-type from the legacy \"cmd\" field and place
   the full top-level object into :content."
  (let ((cmd     (%hash-get obj "cmd"))
        (session (%hash-get obj "session")))
    (list :msg-type cmd
          :session  session
          :content  obj
          :cmd      cmd
          :ok       (%hash-get obj "ok")
          :error    (%hash-get obj "error")
          :data     (%hash-get obj "data")
          :status   (%hash-get obj "status")
          :mode     (%hash-get obj "mode")
          :message  (%hash-get obj "message"))))

(defun %parse-json-response (json-string)
  "Parse a JSON response string into a unified plist (see %parse-5part /
   %parse-legacy-flat). Detects 5-part by the presence of a `header` key."
  (let ((obj (shasht:read-json json-string)))
    (if (and (hash-table-p obj) (nth-value 1 (gethash "header" obj)))
        (%parse-5part obj)
        (%parse-legacy-flat obj))))

(defun cp-parse-response (line)
  "Parse a CP server response.
   JSON (starts with `{`) -> unified plist via %parse-json-response.
   Legacy pipe format     -> list of strings via uiop:split-string."
  (if (and (plusp (length line)) (char= (char line 0) #\{))
      (%parse-json-response line)
      (uiop:split-string line :separator "|")))
