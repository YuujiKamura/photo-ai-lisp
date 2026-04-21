(in-package #:photo-ai-lisp/tests)

;;; Contract: the HTTP handler functions are pure strings-in / string-out,
;;; so we test them directly without starting Hunchentoot. This mirrors
;;; the httptest-style approach used by photo-ai-rust/web/server_test.go:
;;; unit-test the handler layer, stop at the WebSocket / browser boundary.

(5am:def-suite business-ui-suite :description "HTTP handler surface")
(5am:in-suite business-ui-suite)

;; ---- home-handler --------------------------------------------------------

(5am:test home-handler-serves-static-index
  "home-handler returns the static index.html content (> 1KB) and
   injects the ghostty-web URL as a data attribute on <html>."
  (let* ((html (photo-ai-lisp::home-handler)))
    (5am:is (> (length html) 1000))
    (5am:is (search "data-ghostty-url=" html))
    (5am:is (search "photo-ai-lisp" html))
    (5am:is (search "masterList" html))))

(5am:test home-handler-respects-ghostty-web-url
  "The injected data attribute contains whatever *ghostty-web-url* is
   set to at call time."
  (let ((photo-ai-lisp::*ghostty-web-url* "http://example.test:9999/"))
    (let ((html (photo-ai-lisp::home-handler)))
      (5am:is (search "data-ghostty-url=\"http://example.test:9999/\"" html)))))

(5am:test home-handler-fallback-when-static-missing
  "When static/index.html is absent, home-handler returns the redirect
   stub pointing at /cases."
  (let ((photo-ai-lisp::*static-root*
          (uiop:ensure-directory-pathname
           (format nil "/tmp/photo-ai-lisp-missing-~a/"
                   (random 1000000)))))
    (let ((html (photo-ai-lisp::home-handler)))
      (5am:is (search "static/index.html not found" html))
      (5am:is (search "/cases" html)))))

;; ---- list-masters-handler ------------------------------------------------

(defun %with-tmp-masters-dir (thunk)
  "Create a fresh temp masters dir, bind *masters-root* to it, run
   THUNK, clean up. Returns whatever THUNK returns."
  (let* ((tmp (merge-pathnames
               (format nil "photo-ai-lisp-masters-~a/" (random 1000000))
               (uiop:temporary-directory))))
    (ensure-directories-exist tmp)
    (unwind-protect
         (let ((photo-ai-lisp::*masters-root*
                 (uiop:ensure-directory-pathname tmp)))
           (funcall thunk tmp))
      (uiop:delete-directory-tree tmp :validate t :if-does-not-exist :ignore))))

(5am:test list-masters-handler-empty-when-no-csv
  (%with-tmp-masters-dir
    (lambda (_) (declare (ignore _))
      (5am:is (equal "[]" (photo-ai-lisp::list-masters-handler))))))

(5am:test list-masters-handler-reads-csv
  "Given one CSV file in *masters-root*, the handler returns a JSON
   array with one entry whose rows come from that file."
  (%with-tmp-masters-dir
    (lambda (tmp)
      (let ((csv (merge-pathnames "test.csv" tmp)))
        (with-open-file (s csv :direction :output
                               :if-does-not-exist :create
                               :external-format :utf-8)
          (write-line "id,label_ja,parent_id,aliases" s)
          (write-line "a,Alpha,,xa|ya" s)
          (write-line "b,Beta,a," s))
        (let ((json (photo-ai-lisp::list-masters-handler)))
          (5am:is (search "\"file\":\"test\"" json))
          (5am:is (search "\"id\":\"a\"" json))
          (5am:is (search "\"label_ja\":\"Alpha\"" json))
          (5am:is (search "\"label_ja\":\"Beta\"" json))
          (5am:is (search "\"aliases\":[\"xa\",\"ya\"]" json)))))))

(5am:test list-masters-handler-sorts-by-filename
  "Multiple CSVs appear in filename order so the UI gets stable output."
  (%with-tmp-masters-dir
    (lambda (tmp)
      (dolist (name '("zeta.csv" "alpha.csv" "mango.csv"))
        (with-open-file (s (merge-pathnames name tmp)
                           :direction :output
                           :if-does-not-exist :create
                           :external-format :utf-8)
          (write-line "id,label_ja,parent_id,aliases" s)
          (write-line "x,X,," s)))
      (let* ((json (photo-ai-lisp::list-masters-handler))
             (p-alpha (search "\"file\":\"alpha\"" json))
             (p-mango (search "\"file\":\"mango\"" json))
             (p-zeta  (search "\"file\":\"zeta\"" json)))
        (5am:is (and p-alpha p-mango p-zeta))
        (5am:is (< p-alpha p-mango p-zeta))))))

;; ---- case-view-handler: iframe src (regression guard for #28) ------------
;;
;; Bug (2026-04-21 T2.g capture): the template was `"~a/shell?case=~a"`
;; with *ghostty-web-url* defaulting to "/shell", which expanded to
;; "/shell/shell?case=..." — a 404 due to the double /shell segment.
;;
;; Fix: treat *ghostty-web-url* as the full base URL (including any /shell
;; suffix). The template now emits `"~a?case=~a"` verbatim.

(defun %with-tmp-case-root (thunk)
  "Create a fresh temp case-root with one case directory named 'demo-case',
   bind *case-root* to it, run THUNK with the synthesised case-id, then
   clean up."
  (let* ((tmp (merge-pathnames
               (format nil "photo-ai-lisp-case-root-~a/" (random 1000000))
               (uiop:temporary-directory)))
         (case-dir (merge-pathnames "demo-case/" tmp)))
    (ensure-directories-exist case-dir)
    (unwind-protect
         (let ((photo-ai-lisp::*case-root*
                 (uiop:ensure-directory-pathname tmp)))
           (funcall thunk "demo-case"))
      (uiop:delete-directory-tree tmp :validate t :if-does-not-exist :ignore))))

(5am:test case-view-handler-iframe-src-default
  "Default *ghostty-web-url* = \"/shell\" must produce iframe
   src=\"/shell?case=<id>\" — never the historical double \"/shell/shell\"."
  (%with-tmp-case-root
    (lambda (id)
      (let ((photo-ai-lisp::*ghostty-web-url* "/shell"))
        (let ((html (photo-ai-lisp::case-view-handler id)))
          (5am:is (search "src=\"/shell?case=" html)
                  "iframe src must start with /shell?case= for default URL")
          (5am:is (null (search "/shell/shell" html))
                  "iframe src must NOT contain double /shell path"))))))

(5am:test case-view-handler-iframe-src-external-url
  "With GHOSTTY_WEB_URL overridden to a full external URL, the iframe src
   equals that URL plus ?case=<encoded-path> — no implicit /shell suffix."
  (%with-tmp-case-root
    (lambda (id)
      (let ((photo-ai-lisp::*ghostty-web-url* "http://host:9000/term"))
        (let ((html (photo-ai-lisp::case-view-handler id)))
          (5am:is (search "src=\"http://host:9000/term?case=" html)
                  "iframe src must use the base URL verbatim + ?case=")
          (5am:is (null (search "/term/shell" html))
                  "template must not append /shell to an external base URL"))))))
