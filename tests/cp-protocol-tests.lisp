(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; Unit tests for src/cp-protocol.lisp
;;;
;;; Phase 1 (G1.a, issue #30): messages are built as 5-part envelopes:
;;;   header / parent_header / metadata / content / buffers
;;; The content object keeps the current flat payload fields (cmd/from/msg/
;;; session/...) for wire compatibility with deckpilot until G1.c negotiation.

;;; --- helpers ------------------------------------------------------------

(defun %parse-top (json-string)
  "Parse JSON-STRING to a hash-table via shasht (bypassing cp-parse-response)."
  (shasht:read-json json-string))

(defun %hg (h k)
  "Short gethash alias used in these tests."
  (gethash k h))

;;; --- make-cp-*: legacy substring checks (still pass under 5-part) -------

(test cp-protocol-make-input
  (is (search "\"cmd\":\"INPUT\""         (photo-ai-lisp:make-cp-input "hello")))
  (is (search "\"msg\":\"aGVsbG8=\""      (photo-ai-lisp:make-cp-input "hello")))
  (is (search "\"from\":\"test\""         (photo-ai-lisp:make-cp-input "hello" :from "test")))
  (is (search "\"session\":\"sess-1\""    (photo-ai-lisp:make-cp-input "hello" :session-id "sess-1"))))

(test cp-protocol-make-tail
  (is (search "\"cmd\":\"SHOW\""          (photo-ai-lisp:make-cp-tail)))
  (is (search "\"lines\":50"              (photo-ai-lisp:make-cp-tail :n 50)))
  (is (search "\"session\":\"sess-1\""    (photo-ai-lisp:make-cp-tail :session-id "sess-1"))))

(test cp-protocol-make-state
  (is (search "\"cmd\":\"STATE\""         (photo-ai-lisp:make-cp-state)))
  (is (search "\"session\":\"sess-1\""    (photo-ai-lisp:make-cp-state "sess-1"))))

(test cp-protocol-make-list-tabs
  (is (search "\"cmd\":\"LIST\""          (photo-ai-lisp:make-cp-list-tabs))))

;;; --- cp-parse-response: legacy flat + round-trip ------------------------

(test cp-protocol-parse-response
  ;; Flat JSON response (legacy server) should still give the plist keys
  ;; existing callers rely on.
  (let ((resp (photo-ai-lisp:cp-parse-response "{\"cmd\":\"INPUT\",\"ok\":true,\"message\":\"sent\"}")))
    (is (getf resp :ok))
    (is (string= "INPUT" (getf resp :cmd)))
    (is (string= "sent"  (getf resp :message))))

  ;; Flat JSON error response
  (let ((resp (photo-ai-lisp:cp-parse-response "{\"ok\":false,\"error\":\"session not found\"}")))
    (is (not (getf resp :ok)))
    (is (string= "session not found" (getf resp :error))))

  ;; Legacy pipe format should still be split into strings
  (is (equal '("OK" "legacy" "parts")
             (photo-ai-lisp:cp-parse-response "OK|legacy|parts"))))

;;; --- G1.a 5-part envelope new tests -------------------------------------

(test envelope-5part-roundtrip
  "make-cp-input -> cp-parse-response round-trips msg-type / session / content."
  (let* ((json (photo-ai-lisp:make-cp-input "hello" :session-id "sess-rt"))
         (resp (photo-ai-lisp:cp-parse-response json)))
    (is (string= "INPUT"   (getf resp :msg-type)))
    (is (string= "sess-rt" (getf resp :session)))
    (let ((content (getf resp :content)))
      (is (hash-table-p content))
      (is (string= "INPUT"          (%hg content "cmd")))
      (is (string= "photo-ai-lisp"  (%hg content "from")))
      (is (string= "sess-rt"        (%hg content "session")))
      ;; msg is base64("hello")
      (is (string= "aGVsbG8="       (%hg content "msg"))))))

(test envelope-5part-header-fields-present
  "Header must carry the fixed schema: msg_id (36ch), date ending in Z,
   version 5.4, msg_type INPUT, username photo-ai-lisp."
  (let* ((json   (photo-ai-lisp:make-cp-input "x" :session-id "s1"))
         (top    (%parse-top json))
         (header (%hg top "header")))
    (is (hash-table-p header)
        "top-level header must be a JSON object")
    ;; msg_id: canonical UUID string is 36 chars (8-4-4-4-12 + hyphens).
    (let ((msg-id (%hg header "msg_id")))
      (is (stringp msg-id))
      (is (= 36 (length msg-id))
          (format nil "msg_id length expected 36, got ~D (~A)" (length msg-id) msg-id)))
    ;; date: RFC3339 with Z suffix and sub-second precision.
    (let ((date (%hg header "date")))
      (is (stringp date))
      (is (plusp (length date)))
      (is (char= #\Z (char date (1- (length date))))
          (format nil "date must end with Z: ~A" date))
      ;; sub-second precision implies a '.' before the Z.
      (is (find #\. date)
          (format nil "date must contain sub-second precision: ~A" date)))
    ;; fixed fields
    (is (string= "5.4"            (%hg header "version")))
    (is (string= "INPUT"          (%hg header "msg_type")))
    (is (string= "photo-ai-lisp"  (%hg header "username")))
    (is (string= "s1"             (%hg header "session")))
    ;; companion parts must exist and be the right empty shapes.
    (is (hash-table-p (%hg top "parent_header"))
        "parent_header must serialise as an empty JSON object")
    (is (zerop (hash-table-count (%hg top "parent_header"))))
    (is (hash-table-p (%hg top "metadata")))
    (is (zerop (hash-table-count (%hg top "metadata"))))
    (let ((buffers (%hg top "buffers")))
      (is (or (vectorp buffers) (listp buffers))
          "buffers must be JSON array shape")
      (is (zerop (length buffers))))))

(test envelope-5part-msg-id-unique
  "Two consecutive make-cp-input calls must mint distinct msg_id values —
   guards against a helper that caches the first UUID."
  (let* ((j1 (photo-ai-lisp:make-cp-input "a"))
         (j2 (photo-ai-lisp:make-cp-input "b"))
         (id1 (%hg (%hg (%parse-top j1) "header") "msg_id"))
         (id2 (%hg (%hg (%parse-top j2) "header") "msg_id")))
    (is (stringp id1))
    (is (stringp id2))
    (is (not (string= id1 id2))
        (format nil "msg_id should be unique per call: ~A vs ~A" id1 id2))))

(test envelope-legacy-flat-still-parses
  "A hand-crafted legacy flat envelope (no `header` key) must still parse
   into the unified accessor shape with msg-type synthesised from `cmd`."
  (let* ((json "{\"cmd\":\"INPUT\",\"from\":\"photo-ai-lisp\",\"msg\":\"aGVsbG8=\",\"session\":\"demo\"}")
         (resp (photo-ai-lisp:cp-parse-response json)))
    (is (string= "INPUT" (getf resp :msg-type)))
    (is (string= "demo"  (getf resp :session)))
    ;; Legacy accessors keep working.
    (is (string= "INPUT" (getf resp :cmd)))
    ;; :content exposes the full top-level object.
    (let ((content (getf resp :content)))
      (is (hash-table-p content))
      (is (string= "INPUT"         (%hg content "cmd")))
      (is (string= "photo-ai-lisp" (%hg content "from")))
      (is (string= "demo"          (%hg content "session"))))))
