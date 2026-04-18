(in-package #:photo-ai-lisp/tests)

;;; Policy directive #01 — spec-as-tests for src/case.lisp.
;;;
;;; These tests define the acceptance for the case CLOS model. The
;;; src/case.lisp stubs currently signal UNIMPLEMENTED for every
;;; function, so every test in this suite fails on RED until the
;;; Codex atoms land. Do NOT mark any of these tests SKIP to hide
;;; red — red IS the spec.
;;;
;;; The parent suite is photo-ai-lisp-tests; no sub-suite is declared
;;; because these all stand at the same level as existing feature
;;; tests.

(in-suite photo-ai-lisp-tests)

;;; ========================================================================
;;; Class shape + direct constructor
;;; ========================================================================

(test case-class-is-defined
  (is-true (find-class 'photo-ai-lisp:photo-case nil)
           "photo-ai-lisp:photo-case must be a defined class"))

(test case-make-photo-case-stores-all-slots
  (let ((c (photo-ai-lisp:make-photo-case
            :path #P"C:/tmp/case1/"
            :name "TestCase"
            :masters-dir #P"C:/tmp/case1/masters/"
            :reference-path #P"C:/tmp/case1/case.xlsx")))
    (is (equal #P"C:/tmp/case1/"             (photo-ai-lisp:photo-case-path c)))
    (is (equal "TestCase"                    (photo-ai-lisp:photo-case-name c)))
    (is (equal #P"C:/tmp/case1/masters/"     (photo-ai-lisp:photo-case-masters-dir c)))
    (is (equal #P"C:/tmp/case1/case.xlsx"    (photo-ai-lisp:photo-case-reference-path c)))))

(test case-make-photo-case-defaults-nil
  (let ((c (photo-ai-lisp:make-photo-case :path #P"C:/tmp/x/")))
    (is (null (photo-ai-lisp:photo-case-name c)))
    (is (null (photo-ai-lisp:photo-case-masters-dir c)))
    (is (null (photo-ai-lisp:photo-case-reference-path c)))))

;;; ========================================================================
;;; case-from-directory: filesystem-aware constructor
;;; ========================================================================

(test case-from-directory-empty-dir-sets-path-only
  (uiop:with-temporary-file (:pathname tmp)
    (declare (ignore tmp)))
  (let ((dir (uiop:ensure-directory-pathname
              (uiop:with-temporary-file (:pathname p :keep t)
                (declare (ignore p))
                (merge-pathnames (format nil "phoai-test-~a/" (random 100000))
                                 (uiop:temporary-directory))))))
    (ensure-directories-exist dir)
    (unwind-protect
        (let ((c (photo-ai-lisp:case-from-directory dir)))
          (is (uiop:pathname-equal dir (photo-ai-lisp:photo-case-path c))
              "path slot must equal the directory")
          (is (null (photo-ai-lisp:photo-case-reference-path c))
              "no case.xlsx -> reference-path must be nil"))
      (uiop:delete-directory-tree dir :validate t))))

(test case-from-directory-picks-up-case-xlsx
  (let ((dir (uiop:ensure-directory-pathname
              (merge-pathnames (format nil "phoai-test-~a/" (random 100000))
                               (uiop:temporary-directory)))))
    (ensure-directories-exist dir)
    (let ((xlsx (merge-pathnames "case.xlsx" dir)))
      (with-open-file (s xlsx :direction :output :if-exists :supersede)
        (format s "placeholder"))
      (unwind-protect
          (let ((c (photo-ai-lisp:case-from-directory dir)))
            (is (uiop:pathname-equal xlsx (photo-ai-lisp:photo-case-reference-path c))
                "case.xlsx in the dir must populate reference-path"))
        (uiop:delete-directory-tree dir :validate t)))))

(test case-from-directory-picks-up-masters-subdir
  (let ((dir (uiop:ensure-directory-pathname
              (merge-pathnames (format nil "phoai-test-~a/" (random 100000))
                               (uiop:temporary-directory)))))
    (ensure-directories-exist dir)
    (let ((masters (uiop:ensure-directory-pathname
                    (merge-pathnames "masters/" dir))))
      (ensure-directories-exist masters)
      (unwind-protect
          (let ((c (photo-ai-lisp:case-from-directory dir)))
            (is (uiop:pathname-equal masters (photo-ai-lisp:photo-case-masters-dir c))
                "masters/ subdir must populate masters-dir"))
        (uiop:delete-directory-tree dir :validate t)))))

;;; ========================================================================
;;; find-case: memoizing / find-or-create
;;; ========================================================================

(test case-find-case-returns-same-object-for-same-path
  (let ((dir (uiop:ensure-directory-pathname
              (merge-pathnames (format nil "phoai-test-~a/" (random 100000))
                               (uiop:temporary-directory)))))
    (ensure-directories-exist dir)
    (unwind-protect
        (let ((c1 (photo-ai-lisp:find-case dir))
              (c2 (photo-ai-lisp:find-case dir)))
          (is (eq c1 c2)
              "find-case must cache — same path -> same object identity"))
      (uiop:delete-directory-tree dir :validate t))))

;;; ========================================================================
;;; Session registry
;;; ========================================================================

(test case-register-and-lookup-session
  (photo-ai-lisp:clear-session "spec-sess-A")
  (let ((c (photo-ai-lisp:make-photo-case :path #P"C:/tmp/")))
    (photo-ai-lisp:register-session "spec-sess-A" c)
    (is (eq c (photo-ai-lisp:lookup-session "spec-sess-A"))
        "lookup must return the exact object passed to register")
    (photo-ai-lisp:clear-session "spec-sess-A")))

(test case-lookup-session-missing-returns-nil
  (photo-ai-lisp:clear-session "spec-sess-missing")
  (is (null (photo-ai-lisp:lookup-session "spec-sess-missing"))
      "unknown session id -> nil, not error"))

(test case-register-session-overwrites
  (let ((c1 (photo-ai-lisp:make-photo-case :path #P"C:/tmp/" :name "A"))
        (c2 (photo-ai-lisp:make-photo-case :path #P"C:/tmp/" :name "B")))
    (photo-ai-lisp:register-session "spec-sess-B" c1)
    (photo-ai-lisp:register-session "spec-sess-B" c2)
    (is (eq c2 (photo-ai-lisp:lookup-session "spec-sess-B")))
    (photo-ai-lisp:clear-session "spec-sess-B")))

(test case-clear-session-is-idempotent
  (photo-ai-lisp:clear-session "spec-sess-never-existed")
  (photo-ai-lisp:clear-session "spec-sess-never-existed")
  (is (null (photo-ai-lisp:lookup-session "spec-sess-never-existed"))))

;;; ========================================================================
;;; build-case-env: pure function, exact alist shape
;;; ========================================================================

(defun %env-value (alist name)
  (cdr (assoc name alist :test #'string=)))

(test case-build-env-full-slots
  (let* ((c (photo-ai-lisp:make-photo-case
             :path           #P"C:/tmp/case1/"
             :name           "TestCase"
             :masters-dir    #P"C:/tmp/case1/masters/"
             :reference-path #P"C:/tmp/case1/case.xlsx"))
         (env (photo-ai-lisp:build-case-env c)))
    (is (listp env) "build-case-env returns a list (alist)")
    (is (search "case1" (%env-value env "PHOTO_AI_CASE_PATH"))
        "PHOTO_AI_CASE_PATH must carry the case root")
    (is (equal "TestCase" (%env-value env "PHOTO_AI_CASE_NAME"))
        "PHOTO_AI_CASE_NAME must equal the name slot")
    (is (search "masters" (%env-value env "PHOTO_AI_MASTERS_DIR"))
        "PHOTO_AI_MASTERS_DIR must carry the masters dir")))

(test case-build-env-nil-slots-become-empty-strings
  (let* ((c   (photo-ai-lisp:make-photo-case :path #P"C:/tmp/x/"))
         (env (photo-ai-lisp:build-case-env c)))
    (is (equal "" (%env-value env "PHOTO_AI_CASE_NAME"))
        "nil name -> empty string (not missing, not nil)")
    (is (equal "" (%env-value env "PHOTO_AI_MASTERS_DIR"))
        "nil masters-dir -> empty string")))

(test case-build-env-has-all-three-keys
  (let* ((c   (photo-ai-lisp:make-photo-case :path #P"C:/tmp/y/"))
         (env (photo-ai-lisp:build-case-env c)))
    (dolist (k '("PHOTO_AI_CASE_PATH" "PHOTO_AI_CASE_NAME" "PHOTO_AI_MASTERS_DIR"))
      (is-true (assoc k env :test #'string=)
               "env must contain key ~a" k))))

;;; ========================================================================
;;; parse-shell-case-query: pure URL query parser
;;; ========================================================================

(test case-parse-query-present
  (is (equal "C:/cases/foo/"
             (photo-ai-lisp:parse-shell-case-query
              "case=C%3A%2Fcases%2Ffoo%2F"))
      "case= parameter must be URL-decoded"))

(test case-parse-query-absent
  (is (null (photo-ai-lisp:parse-shell-case-query ""))
      "empty query -> nil")
  (is (null (photo-ai-lisp:parse-shell-case-query "foo=1&bar=2"))
      "no case= -> nil"))

(test case-parse-query-mixed-with-other-params
  (is (equal "C:/cases/bar/"
             (photo-ai-lisp:parse-shell-case-query
              "foo=1&case=C%3A%2Fcases%2Fbar%2F&baz=2"))
      "case= parsed correctly when other params present"))

(test case-parse-query-empty-value
  (is (or (null (photo-ai-lisp:parse-shell-case-query "case="))
          (equal "" (photo-ai-lisp:parse-shell-case-query "case=")))
      "case= with empty value -> nil or empty string (impl choice)"))

;;; ========================================================================
;;; api-session-handler: JSON shape
;;; ========================================================================

(test case-api-session-returns-registered-case-json
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply))
        (c (photo-ai-lisp:make-photo-case
            :path #P"C:/tmp/api-test/" :name "ApiCase")))
    (unwind-protect
        (progn
          (photo-ai-lisp:register-session "api-test-1" c)
          (let ((body (photo-ai-lisp:api-session-handler "api-test-1")))
            (is (stringp body)
                "handler must return a string (JSON body)")
            (is (search "ApiCase" body)
                "handler JSON must mention case name")
            (is (search "api-test" body)
                "handler JSON must include the case path somewhere")))
      (photo-ai-lisp:clear-session "api-test-1"))))

(test case-api-session-unknown-returns-error-shape
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (photo-ai-lisp:clear-session "api-test-missing")
    (let ((body (photo-ai-lisp:api-session-handler "api-test-missing")))
      (is (stringp body))
      (is (search "error" body)
          "unknown session -> JSON body mentions 'error'"))))
