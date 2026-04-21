(in-package #:photo-ai-lisp)

;;; Issue #29 (C1) — Tier 3 usage log auto-write.
;;;
;;; Spec is frozen in docs/tier-3/usage-log-format.md:
;;;   - append-only, one event per line, tab-separated
;;;   - ISO 8601 UTC with ms precision + 'Z' suffix
;;;   - closed verb set (INPUT/SHOW/STATE/LIST/BOOT/SHUTDOWN)
;;;   - protocol violations land in usage-errors.log so the main log
;;;     never contains an unknown verb
;;;
;;; The counting script for the Fri verdict greps the main log for
;;; "\tINPUT\t" lines with non-zero bytes; any extra discipline belongs
;;; in that script, not here.

(defvar *usage-log-path*
  (merge-pathnames ".photo-ai-lisp/usage.log"
                   (user-homedir-pathname))
  "Append-only usage log path. Tests rebind to a temp file.")

(defvar *usage-errors-log-path*
  (merge-pathnames ".photo-ai-lisp/usage-errors.log"
                   (user-homedir-pathname))
  "Spec-violation sink. Unknown verb or bad bytes land here.")

(defparameter +usage-log-verbs+
  '("INPUT" "SHOW" "STATE" "LIST" "BOOT" "SHUTDOWN")
  "Closed verb set. Changing this is a spec change, not a code change.")

(defun %usage-log-iso8601-utc-now ()
  "Return current UTC instant as ISO 8601 with ms precision + 'Z'.
   Example: 2026-04-21T10:30:45.123Z.

   Seconds come from GET-UNIVERSAL-TIME (second resolution, UTC via
   time-zone 0). The ms field is derived from GET-INTERNAL-REAL-TIME
   modulo 1000; it is monotonic within a process but not calendar-
   synchronized, which is accepted for dogfood telemetry.

   Caveat: the ms field is NOT phase-aligned to the UTC second
   boundary. GET-INTERNAL-REAL-TIME starts at an arbitrary process-
   local epoch, so (mod ticks 1000) produces values that roll over at
   some implementation-defined offset rather than exactly when the
   UTC second ticks. For the Fri 2026-04-24 Tier 3 verdict this is
   fine because the counting script only greps '\\tINPUT\\t' lines and
   ignores intra-second ordering. The follow-up atom #30 G5.b may
   swap this to LOCAL-TIME:NOW for proper phase alignment."
  (let* ((ut (get-universal-time))
         (tick-ms (/ internal-time-units-per-second 1000))
         (ms (if (plusp tick-ms)
                 (mod (floor (get-internal-real-time) tick-ms) 1000)
                 0)))
    (multiple-value-bind (s mi h d mo y) (decode-universal-time ut 0)
      (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D.~3,'0DZ"
              y mo d h mi s ms))))

(defun usage-log-utf8-byte-count (s)
  "Return UTF-8 octet count for string S. NIL → 0.
   Walks codepoints and sums the UTF-8 width; avoids pulling babel
   as an explicit dep for a 5-line calculation."
  (if (null s)
      0
      (let ((n 0))
        (loop for ch across s do
              (let ((cp (char-code ch)))
                (incf n (cond
                          ((< cp #x80)     1)
                          ((< cp #x800)    2)
                          ((< cp #x10000)  3)
                          (t               4)))))
        n)))

(defun %usage-log-ensure-parent (path)
  "Create parent directory of PATH if missing. Idempotent."
  (ensure-directories-exist
   (make-pathname :defaults path :name nil :type nil)))

(defun %usage-log-append-line (path line)
  "Append LINE + newline to PATH, creating the parent dir if needed."
  (%usage-log-ensure-parent path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :append
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string line stream)
    (terpri stream)))

(defun write-usage-log-event (&key verb session bytes)
  "Append one event to *USAGE-LOG-PATH* per docs/tier-3/usage-log-format.md.

   VERB    — must be in +USAGE-LOG-VERBS+; anything else (incl. NIL)
             writes to *USAGE-ERRORS-LOG-PATH* and this function
             returns NIL.
   SESSION — deckpilot session string; NIL or empty → '-' (BOOT/SHUTDOWN
             convention).
   BYTES   — non-negative integer; anything else routes to the errors
             log.

   Returns T iff a line was written to the main log."
  (cond
    ((not (and verb
               (stringp verb)
               (member verb +usage-log-verbs+ :test #'string=)))
     (%usage-log-append-line
      *usage-errors-log-path*
      (format nil "~A~CUNKNOWN-VERB~C~A~C~A"
              (%usage-log-iso8601-utc-now) #\Tab #\Tab
              (or verb "(nil)") #\Tab (if bytes (prin1-to-string bytes) "-")))
     nil)
    ((not (and (integerp bytes) (>= bytes 0)))
     (%usage-log-append-line
      *usage-errors-log-path*
      (format nil "~A~CBAD-BYTES~C~A~C~A"
              (%usage-log-iso8601-utc-now) #\Tab #\Tab
              verb #\Tab (prin1-to-string bytes)))
     nil)
    (t
     (let ((sess (if (and session
                          (stringp session)
                          (plusp (length session)))
                     session
                     "-")))
       (%usage-log-append-line
        *usage-log-path*
        (format nil "~A~C~A~C~A~C~D"
                (%usage-log-iso8601-utc-now) #\Tab
                verb #\Tab sess #\Tab bytes))
       t))))
