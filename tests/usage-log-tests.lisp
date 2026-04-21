(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; Acceptance specs for src/usage-log.lisp (issue #29 / C1).
;;; Spec reference: docs/tier-3/usage-log-format.md.

(defmacro %with-temp-log-paths ((main-var errors-var) &body body)
  "Rebind *usage-log-path* and *usage-errors-log-path* to unique temp
   files so tests never touch ~/.photo-ai-lisp/. Files are deleted
   after BODY. MAIN-VAR / ERRORS-VAR are bound to the pathnames."
  `(let* ((,main-var   (uiop:with-temporary-file (:pathname p :keep t) p))
          (,errors-var (uiop:with-temporary-file (:pathname p :keep t) p)))
     ;; We only wanted the pathnames; the files exist but are empty — that
     ;; is fine because :if-exists :append is the open mode in write path.
     (unwind-protect
          (let ((photo-ai-lisp:*usage-log-path*        ,main-var)
                (photo-ai-lisp:*usage-errors-log-path* ,errors-var))
            ,@body)
       (ignore-errors (delete-file ,main-var))
       (ignore-errors (delete-file ,errors-var)))))

(defun %read-file-lines (path)
  "Return a list of lines in PATH (without trailing newlines).
   Missing file → NIL."
  (when (probe-file path)
    (with-open-file (s path :direction :input :external-format :utf-8)
      (loop for line = (read-line s nil nil)
            while line
            collect line))))

;; ---- C1-1 : happy path — one INPUT line in the main log, none in errors -----

(5am:test usage-log-writes-input-event-to-main-log
  "write-usage-log-event with a known verb and non-negative bytes must
   append exactly one tab-separated line to *usage-log-path* with the
   shape <iso8601>\\tINPUT\\t<session>\\t<bytes>, and must not touch
   *usage-errors-log-path*."
  (%with-temp-log-paths (main err)
    (5am:is (eq t (photo-ai-lisp:write-usage-log-event
                   :verb "INPUT" :session "ghostty-12345" :bytes 21))
            "returns T on a successful main-log write")
    (let ((lines (%read-file-lines main)))
      (5am:is (= 1 (length lines))
              "main log should contain exactly one line")
      (let* ((line   (first lines))
             (fields (uiop:split-string line :separator (list #\Tab))))
        (5am:is (= 4 (length fields))
                "line should have exactly 4 tab-separated fields")
        (5am:is (equal "INPUT" (second fields))
                "verb field should be INPUT")
        (5am:is (equal "ghostty-12345" (third fields))
                "session field should echo the given session id")
        (5am:is (equal "21" (fourth fields))
                "bytes field should be the decimal representation")
        (5am:is (search "T" (first fields))
                "timestamp should contain the ISO 8601 'T' separator")
        (5am:is (eql #\Z (aref (first fields) (1- (length (first fields)))))
                "timestamp should end with 'Z'")))
    (5am:is (null (%read-file-lines err))
            "errors log should remain empty for a valid event")))

;; ---- C1-2 : protocol violation — unknown verb lands in errors log, not main --

(5am:test usage-log-unknown-verb-goes-to-errors-log
  "An unknown verb must NOT contaminate the main log. The function
   returns NIL and writes a line to *usage-errors-log-path*."
  (%with-temp-log-paths (main err)
    (5am:is (null (photo-ai-lisp:write-usage-log-event
                   :verb "DANCE" :session "s" :bytes 1))
            "returns NIL on spec violation")
    (5am:is (null (%read-file-lines main))
            "main log must stay empty for unknown verbs")
    (let ((lines (%read-file-lines err)))
      (5am:is (= 1 (length lines))
              "errors log should contain exactly one line")
      (5am:is (search "UNKNOWN-VERB" (first lines))
              "errors log line should identify the violation class")
      (5am:is (search "DANCE" (first lines))
              "errors log line should quote the offending verb"))))

;; ---- C1-3 : nil/empty session normalises to '-' (BOOT/SHUTDOWN convention) --

(5am:test usage-log-nil-session-serialises-as-dash
  "NIL or empty session must serialise as '-' in the session column,
   matching the BOOT/SHUTDOWN convention in the spec."
  (%with-temp-log-paths (main err)
    (declare (ignore err))
    (photo-ai-lisp:write-usage-log-event :verb "BOOT" :session nil :bytes 0)
    (photo-ai-lisp:write-usage-log-event :verb "SHUTDOWN" :session "" :bytes 0)
    (let ((lines (%read-file-lines main)))
      (5am:is (= 2 (length lines))
              "main log should have two lines (BOOT + SHUTDOWN)")
      (dolist (l lines)
        (let ((fields (uiop:split-string l :separator (list #\Tab))))
          (5am:is (equal "-" (third fields))
                  "nil/empty session must render as '-'"))))))
