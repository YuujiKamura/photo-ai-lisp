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
  "Generates an INPUT command string. TEXT is encoded to base64."
  (format nil "INPUT|~a|~a~@[|~a~]"
          from
          (%encode-base64 text)
          session-id))

(defun make-cp-tail (&key (n 20) session-id)
  "Generates a TAIL command string."
  (format nil "TAIL|~d~@[|~a~]" n session-id))

(defun make-cp-state (&optional session-id)
  "Generates a STATE command string."
  (format nil "STATE~@[|~a~]" session-id))

(defun make-cp-list-tabs ()
  "Generates a LIST_TABS command string."
  "LIST_TABS")

(defun cp-parse-response (line)
  "Parses a raw line from the CP server into a list of parts."
  (uiop:split-string line :separator "|"))
