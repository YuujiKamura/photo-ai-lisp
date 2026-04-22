;;;; scripts/preset-live-smoke.lisp
;;;; Smoke test for the live-edit preset API (NEW / REWRITE / DELETE /
;;;; DEPLOY).  Starts the server on a dedicated port, drives it with
;;;; drakma, asserts each side effect, writes deploy output, verifies
;;;; reload survival, then cleans up.  Prints "SMOKE OK" on success or
;;;; "SMOKE FAIL: ..." and uiop:quit 1.

(load "~/quicklisp/setup.lisp")
(let ((root (make-pathname :name nil :type nil :version nil
                           :defaults (merge-pathnames
                                       (make-pathname :directory '(:relative :up))
                                       (make-pathname :name nil :type nil :version nil
                                                      :defaults (or *load-pathname*
                                                                    *default-pathname-defaults*))))))
  (push root asdf:*central-registry*))
(ql:quickload '(:photo-ai-lisp) :silent t)

(in-package #:photo-ai-lisp)

(defvar *smoke-port* 8097)
(defvar *smoke-base* (format nil "http://127.0.0.1:~a" *smoke-port*))

(defun %smoke-fail (fmt &rest args)
  (format *error-output* "SMOKE FAIL: ")
  (apply #'format *error-output* fmt args)
  (format *error-output* "~%")
  (uiop:quit 1))

(defun %http (method path &key body expect)
  "Shell out to curl so arbitrary HTTP methods (NEW / REWRITE / DEPLOY)
   go through — drakma's method whitelist rejects them.  Returns the
   response body as a string.  If EXPECT is an integer, assert status
   matches by sending -w '\\n%{http_code}' as a trailing line."
  (let* ((fmt (concatenate 'string (string #\Newline)
                                   "__STATUS__%{http_code}"))
         (args (append (list "curl" "-sS"
                             "-X" method
                             "-H" "Content-Type: application/json"
                             "-w" fmt)
                       (when body (list "--data-binary" body))
                       (list (format nil "~a~a" *smoke-base* path))))
         (raw (uiop:run-program args :output :string
                                     :error-output :string
                                     :ignore-error-status t))
         (marker (search "__STATUS__" raw))
         (body-str (if marker (subseq raw 0 (max 0 (1- marker))) raw))
         (status (if marker
                     (parse-integer raw :start (+ marker (length "__STATUS__"))
                                        :junk-allowed t)
                     0)))
    (when expect
      (unless (and status (= status expect))
        (%smoke-fail "~a ~a returned ~a (expected ~a): ~a"
                     method path status expect body-str)))
    body-str))

(defun %preset-names-from-list ()
  (sort (mapcar (lambda (e) (getf e :name))
                (loop for entry across
                      (let ((raw (%http "GET" "/api/presets" :expect 200)))
                        (shasht:read-json raw))
                      collect (list :name (gethash "name" entry))))
        #'string<))

(format t "[SMOKE] starting server on :~a~%" *smoke-port*)
(start :port *smoke-port*)
(sleep 0.5)

(unwind-protect
     (progn
       ;; 1. baseline: bundled presets exist
       (let ((before (%preset-names-from-list)))
         (format t "[SMOKE] baseline presets: ~a~%" before)
         (unless (find "学習" before :test #'equal)
           (%smoke-fail "bundled preset 学習 missing from baseline: ~a" before)))

       ;; 2. NEW preset
       (%http "POST" "/api/presets/new/smoke-one"
              :body "{\"argv\":[\"echo\",\"hello\"],\"group\":\"テスト\",\"input\":\"first prompt\"}"
              :expect 200)
       (let ((names (%preset-names-from-list)))
         (unless (find "smoke-one" names :test #'equal)
           (%smoke-fail "NEW did not install smoke-one (have ~a)" names)))
       (unless (equal '("echo" "hello") (find-preset-argv "smoke-one"))
         (%smoke-fail "argv mismatch: ~a" (find-preset-argv "smoke-one")))
       (unless (equal "first prompt" (find-preset-input "smoke-one"))
         (%smoke-fail "input mismatch: ~a" (find-preset-input "smoke-one")))
       (unless (equal "テスト" (find-preset-group "smoke-one"))
         (%smoke-fail "group mismatch: ~a" (find-preset-group "smoke-one")))
       (format t "[SMOKE] NEW ok~%")

       ;; 3. REWRITE partial update: only input
       (%http "POST" "/api/presets/rewrite/smoke-one"
              :body "{\"input\":\"second prompt\"}"
              :expect 200)
       (unless (equal "second prompt" (find-preset-input "smoke-one"))
         (%smoke-fail "REWRITE input failed: ~a" (find-preset-input "smoke-one")))
       (unless (equal '("echo" "hello") (find-preset-argv "smoke-one"))
         (%smoke-fail "REWRITE should not touch argv: ~a"
                      (find-preset-argv "smoke-one")))
       (format t "[SMOKE] REWRITE ok (partial update preserved argv)~%")

       ;; 4. DEPLOY: writes presets-live.lisp
       (%http "POST" "/api/presets/deploy" :expect 200)
       (let ((p (merge-pathnames "src/presets-live.lisp" (uiop:getcwd))))
         (unless (probe-file p)
           (%smoke-fail "DEPLOY did not create ~a" p))
         (let ((content (uiop:read-file-string p)))
           (unless (search "\"smoke-one\"" content)
             (%smoke-fail "DEPLOY file missing smoke-one entry (len=~a)"
                          (length content)))
           (unless (search "second prompt" content)
             (%smoke-fail "DEPLOY file missing updated input"))))
       (format t "[SMOKE] DEPLOY ok (presets-live.lisp updated)~%")

       ;; 5. reload:presets-live replays the file → state survives
       (reload-module :presets-live)
       (unless (equal "second prompt" (find-preset-input "smoke-one"))
         (%smoke-fail "state did not survive reload: input=~a"
                      (find-preset-input "smoke-one")))
       (format t "[SMOKE] reload-module :presets-live ok~%")

       ;; 6. DELETE preset
       (%http "POST" "/api/presets/delete/smoke-one" :expect 200)
       (let ((names (%preset-names-from-list)))
         (when (find "smoke-one" names :test #'equal)
           (%smoke-fail "DELETE did not remove smoke-one (have ~a)" names)))
       (when (find-preset "smoke-one")
         (%smoke-fail "find-preset still finds smoke-one after delete"))
       (format t "[SMOKE] DELETE ok~%")

       ;; 7. DELETE nonexistent → 404
       (let ((resp (%http "POST" "/api/presets/delete/does-not-exist")))
         (unless (search "\"ok\":false" resp)
           (%smoke-fail "DELETE of missing preset should fail: ~a" resp)))
       (format t "[SMOKE] DELETE 404-ish ok~%")

       ;; 8. NEW with missing argv → 400
       (let ((resp (%http "POST" "/api/presets/new/bad" :body "{}")))
         (unless (search "\"ok\":false" resp)
           (%smoke-fail "NEW w/o argv should fail: ~a" resp)))
       (format t "[SMOKE] NEW validation ok~%")

       ;; 9. re-deploy to clear smoke-one from the file so repeat runs stay green
       (%http "POST" "/api/presets/deploy" :expect 200)
       (format t "[SMOKE] DEPLOY clean ok~%")

       (format t "SMOKE OK~%")
       (uiop:quit 0))
  (ignore-errors (stop)))
