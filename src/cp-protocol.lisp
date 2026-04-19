(in-package #:photo-ai-lisp)

;;; Issue #17 — CP (Control Plane) Protocol implementation.
;;; Provides generation of structure command strings and parsing of responses.
;;;
;;; Protocol format: COMMAND|arg1|arg2|...
;;; Responses: OK|... or ERR|... or CMD|...

(defun %encode-base64 (string)
  "Encodes STRING to base64 using cl-base64 or similar.
   For now, we use a simple placeholder until we confirm the best library."
  ;; Placeholder: we might need to add cl-base64 to ASD if not present.
  ;; ghostty-web expects standard base64 for INPUT/PASTE.
  (uiop:symbol-call '#:cl-base64 '#:string-to-base64-string string))

(defun make-cp-input (text &key (from "photo-ai-lisp") session-id)
  "Generates an INPUT command in JSON format. TEXT is encoded to base64."
  (format nil "{\"cmd\":\"INPUT\",\"from\":\"~A\",\"msg\":\"~A\",\"session\":\"~A\"}"
          from
          (%encode-base64 text)
          (or session-id "")))

(defun make-cp-tail (&key (n 20) session-id)
  "Generates a TAIL (using SHOW cmd in Deckpilot) command in JSON format."
  (format nil "{\"cmd\":\"SHOW\",\"mode\":\"buffer\",\"session\":\"~A\",\"lines\":~D}"
          (or session-id "")
          n))

(defun make-cp-state (&optional session-id)
  "Generates a STATE command in JSON format."
  (format nil "{\"cmd\":\"STATE\",\"session\":\"~A\"}"
          (or session-id "")))

(defun make-cp-list-tabs ()
  "Generates a LIST command in JSON format."
  "{\"cmd\":\"LIST\"}")

(defun cp-parse-response (line)
  "Parses a raw JSON response from the CP server.
   For now, we handle basic pipe-delimited legacy or raw JSON as a list of parts."
  (if (and (plusp (length line)) (char= (char line 0) #\{))
      (list "JSON" line) ; Higher level will parse JSON
      (uiop:split-string line :separator "|")))
