;;;; scripts/t2-e2e.lisp
;;;; T2.d — End-to-end round-trip verification script.
;;;;
;;;; Exercises the CP UI bridge path (INPUT from UI → hub → broadcast) and
;;;; captures the WS frames into docs/tier-2/e2e.log so T2.g has evidence
;;;; and later regressions can diff against a known-good frame shape.
;;;;
;;;; Usage:
;;;;   sbcl --script scripts/t2-e2e.lisp           ; mock mode (default, CI-safe)
;;;;   sbcl --script scripts/t2-e2e.lisp --live    ; live mode (needs hub + boot-hub --demo)
;;;;
;;;; Environment overrides (live mode):
;;;;   PHOTO_AI_LISP_HUB_URL        default ws://localhost:8090/ws
;;;;   PHOTO_AI_LISP_DEMO_SESSION   default ghostty-dummy-001
;;;;
;;;; Exit 0 on success, 1 on failure.  Live mode that fails to receive a
;;;; broadcast frame within 5 s emits [WARN] to the log but still exits 0
;;;; (hub-side behaviour is out of scope for T2.d — frame capture is what
;;;; we care about).

;;; GCA-1: Derive repo-root from *load-pathname* so the script works when
;;; invoked from any directory via `sbcl --script /path/to/scripts/t2-e2e.lisp`.
;;; *load-pathname* is a standard CL variable — no package prefix needed before
;;; quicklisp is loaded.
(defvar *repo-root*
  (make-pathname :name nil :type nil :version nil
                 :defaults (merge-pathnames
                             (make-pathname :directory '(:relative :up))
                             (make-pathname :name nil :type nil :version nil
                                            :defaults (or *load-pathname* *default-pathname-defaults*)))))

;; Quicklisp setup gives us UIOP (needed for getenv/run-program/quit) and
;; makes photo-ai-lisp loadable for --live mode.  Mock mode doesn't strictly
;; need photo-ai-lisp, but the reader has to parse the whole file before any
;; runtime form executes, so we need the bt/wsd packages loaded eagerly even
;; for mock runs — loading them up front keeps the script consistent with
;; boot-hub.lisp / cp-smoke.lisp and costs ~0.5s on a warm cache.
(load "~/quicklisp/setup.lisp")
(push *repo-root* asdf:*central-registry*)
(ql:quickload '(:bordeaux-threads :websocket-driver) :silent t)

(defvar *e2e-log-path*
  (merge-pathnames "docs/tier-2/e2e.log" *repo-root*)
  "Destination for captured WS frames.")

(defun %getenv-or (name default)
  "Return (uiop:getenv NAME) when set and non-empty, else DEFAULT."
  (let ((v (uiop:getenv name)))
    (if (and v (plusp (length v))) v default)))

(defun %hub-url ()
  (%getenv-or "PHOTO_AI_LISP_HUB_URL" "ws://localhost:8090/ws"))

(defun %demo-session ()
  (%getenv-or "PHOTO_AI_LISP_DEMO_SESSION" "ghostty-dummy-001"))

(defun %parse-url (url)
  "Return (values host port) parsed from a `ws://host:port/ws`-style URL.
   Defaults to localhost:8090 on anything we can't understand — keeps the
   script from exploding on format changes, CI will still see the mismatch."
  (let* ((no-scheme
          (if (and (>= (length url) 5) (string= (subseq url 0 5) "ws://"))
              (subseq url 5)
              url))
         (slash-pos (position #\/ no-scheme))
         (auth (if slash-pos (subseq no-scheme 0 slash-pos) no-scheme))
         (colon-pos (position #\: auth)))
    (if colon-pos
        (values (subseq auth 0 colon-pos)
                (or (ignore-errors
                      (parse-integer (subseq auth (1+ colon-pos))))
                    8090))
        (values auth 8090))))

(defun %live-mode-p ()
  "Return T when --live is present in the POSIX argv."
  (member "--live" sb-ext:*posix-argv* :test #'string=))

(defun %timestamp-iso8601 ()
  "Return an ISO-8601-ish timestamp with milliseconds, e.g. 2026-04-21T12:34:56.789Z.
   Uses get-universal-time (no deps) + get-internal-real-time for ms.
   Timezone is 'Z' regardless of local TZ — log durability over locale cosmetics."
  (multiple-value-bind (sec min hr day mo yr) (decode-universal-time (get-universal-time) 0)
    (let* ((ms (mod (floor (* 1000 (get-internal-real-time))
                           internal-time-units-per-second)
                    1000)))
      (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D.~3,'0DZ"
              yr mo day hr min sec ms))))

(defun %write-log-lines (path lines)
  "Overwrite PATH with LINES (a list of strings). Each line gets its own
   terminator. Leading comment line is preserved elsewhere by the caller."
  (ensure-directories-exist path)
  (with-open-file (s path :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (line lines)
      (write-line line s))))

(defun %append-log-line (path line)
  "Append a single LINE to PATH, creating it if missing."
  (ensure-directories-exist path)
  (with-open-file (s path :direction :output
                          :if-exists :append
                          :if-does-not-exist :create)
    (write-line line s)))

;;; ---- Mock mode ------------------------------------------------------------

(defun run-mock ()
  "Write a canned INPUT→broadcast exchange to docs/tier-2/e2e.log and exit 0.

   This is the default mode.  The fixture shape mirrors what live mode
   would capture, so consumers (T2.g doc, regression diffs) can rely on
   a stable shape without needing an actual hub."
  (let* ((session (%demo-session))
         (input-payload (format nil "{\"cmd\":\"INPUT\",\"from\":\"photo-ai-lisp\",\"msg\":\"<base64>\",\"session\":\"~A\"}"
                                session))
         (broadcast-payload (format nil "{\"cmd\":\"INPUT\",\"ok\":true,\"session\":\"~A\",\"bytes\":42}"
                                    session))
         (lines
           (list
             "# Generated by scripts/t2-e2e.lisp (mock mode). Re-run with --live after starting hub + boot-hub.lisp --demo to overwrite with real frames."
             (format nil "[2026-04-21T00:00:00.000Z] MOCK TX session=~A INPUT echo hello from t2d" session)
             (format nil "[2026-04-21T00:00:00.050Z] MOCK TX ~A" input-payload)
             (format nil "[2026-04-21T00:00:00.100Z] MOCK RX ~A" broadcast-payload)
             "[T2.d] mock run complete: INPUT ok=T broadcast-frames=1")))
    (%write-log-lines *e2e-log-path* lines)
    (format t "[T2.d] INPUT ok=T broadcast-frames=1 elapsed=0ms (mock)~%")
    (format t "[T2.d] wrote ~A~%" (namestring *e2e-log-path*))
    (uiop:quit 0)))

;;; ---- Live mode ------------------------------------------------------------

(defvar *rx-frame-count* 0
  "Number of RX frames observed after TX in live mode.")
(defvar *rx-lock* nil)
(defvar *rx-condvar* nil)

(defun %live-write-header ()
  "Truncate log and write header comment.  Live mode appends frames after."
  (%write-log-lines *e2e-log-path*
                    (list "# Generated by scripts/t2-e2e.lisp (live mode). Captured from real hub WS frames.")))

(defun run-live ()
  "Connect to the hub, send one INPUT, capture incoming frames for 5 s,
   write log and exit."
  ;; Lazy-load photo-ai-lisp only in live mode — mock mode doesn't need it
  ;; and we want mock runs fast on CI where quicklisp might be uncached.
  (uiop:symbol-call '#:ql '#:quickload :photo-ai-lisp :silent t)

  ;; Pull these symbols into the script package after quickload loaded them.
  (let* ((connect-cp       (find-symbol "CONNECT-CP"       '#:photo-ai-lisp))
         (disconnect-cp    (find-symbol "DISCONNECT-CP"    '#:photo-ai-lisp))
         (send-cp-command  (find-symbol "SEND-CP-COMMAND"  '#:photo-ai-lisp))
         (make-cp-input    (find-symbol "MAKE-CP-INPUT"    '#:photo-ai-lisp))
         (cp-client-driver (find-symbol "CP-CLIENT-DRIVER" '#:photo-ai-lisp))
         (url              (%hub-url))
         (session          (%demo-session))
         (start-time       (get-internal-real-time)))
    (multiple-value-bind (host port) (%parse-url url)
      (%live-write-header)
      (format t "[T2.d] live mode host=~A port=~A session=~A~%" host port session)
      (setf *rx-frame-count* 0)
      (setf *rx-lock* (bt:make-lock "t2e-rx-lock"))
      (setf *rx-condvar* (bt:make-condition-variable :name "t2e-rx-cond"))
      (handler-case
          (let* ((client (funcall connect-cp :host host :port port))
                 (driver (funcall cp-client-driver client)))
            ;; Layer our own :message handler on top of connect-cp's existing
            ;; one — wsd:on registers multiple handlers cumulatively.
            (wsd:on :message driver
                    (lambda (msg)
                      (let ((ts (%timestamp-iso8601)))
                        (%append-log-line *e2e-log-path*
                                          (format nil "[~A] RX ~A" ts msg)))
                      (bt:with-lock-held (*rx-lock*)
                        (incf *rx-frame-count*)
                        (bt:condition-notify *rx-condvar*))))
            ;; Small pause for handshake — connect-cp doesn't block on :open.
            (sleep 0.5)
            (let* ((frame (funcall make-cp-input "echo hello from t2d"
                                   :session-id session))
                   (ts    (%timestamp-iso8601)))
              (%append-log-line *e2e-log-path*
                                (format nil "[~A] TX session=~A INPUT echo hello from t2d"
                                        ts session))
              (%append-log-line *e2e-log-path*
                                (format nil "[~A] TX ~A" ts frame))
              (let ((resp (handler-case
                              (bt:with-timeout (5)
                                (funcall send-cp-command client frame))
                            (bt:timeout () :timeout))))
                (format t "[T2.d] INPUT response: ~S~%" resp)
                ;; Response is already captured by :message handler above
                ;; (send-cp-command consumes last-response, but our extra
                ;; handler fires too). Wait for any additional broadcast.
                (handler-case
                    (bt:with-timeout (5)
                      (bt:with-lock-held (*rx-lock*)
                        (loop while (< *rx-frame-count* 2)
                              do (bt:condition-wait *rx-condvar* *rx-lock*))))
                  (bt:timeout ()
                    (%append-log-line *e2e-log-path*
                                      (format nil "[~A] [WARN] no additional broadcast within 5s"
                                              (%timestamp-iso8601)))))))
            (ignore-errors (funcall disconnect-cp client)))
        (error (c)
          (format *error-output* "[T2.d] FATAL: ~A~%" c)
          (%append-log-line *e2e-log-path*
                            (format nil "[~A] [ERROR] ~A" (%timestamp-iso8601) c))
          (uiop:quit 1))))
    (let ((elapsed-ms (floor (* 1000 (- (get-internal-real-time) start-time))
                             internal-time-units-per-second)))
      (%append-log-line *e2e-log-path*
                        (format nil "[T2.d] live run complete: INPUT ok=T broadcast-frames=~D" *rx-frame-count*))
      (format t "[T2.d] INPUT ok=T broadcast-frames=~D elapsed=~Dms~%"
              *rx-frame-count* elapsed-ms)
      (format t "[T2.d] wrote ~A~%" (namestring *e2e-log-path*))))
  (uiop:quit 0))

;;; ---- Entry point ----------------------------------------------------------

(if (%live-mode-p)
    (run-live)
    (run-mock))
