(in-package #:photo-ai-lisp/tests)

;;; Policy directive #04 — spec-as-tests for src/business-ui.lisp.
;;;
;;; These deftests define acceptance for the minimum business UI:
;;; case list + case view (left meta, right embedded /shell).
;;; Red until the atoms under .dispatch/codex-business-ui-NN-*.md
;;; land. Do not weaken these to pass; red is the spec.

(in-suite photo-ai-lisp-tests)

;;; ========================================================================
;;; Config + scan
;;; ========================================================================

(test business-ui-case-root-is-bound
  (is-true (boundp 'photo-ai-lisp:*case-root*)
           "photo-ai-lisp:*case-root* must be a defvar'd pathname"))

(defun %fresh-case-root ()
  (uiop:ensure-directory-pathname
   (merge-pathnames (format nil "phoai-ui-test-~a/" (random 100000))
                    (uiop:temporary-directory))))

(test business-ui-scan-cases-empty-dir
  (let ((root (%fresh-case-root)))
    (ensure-directories-exist root)
    (unwind-protect
        (let ((photo-ai-lisp:*case-root* root))
          (is (null (photo-ai-lisp:scan-cases))
              "empty root -> no cases"))
      (uiop:delete-directory-tree root :validate t))))

(test business-ui-scan-cases-finds-subdirs
  (let ((root (%fresh-case-root)))
    (ensure-directories-exist root)
    (ensure-directories-exist
     (uiop:ensure-directory-pathname (merge-pathnames "case-a/" root)))
    (ensure-directories-exist
     (uiop:ensure-directory-pathname (merge-pathnames "case-b/" root)))
    (unwind-protect
        (let* ((photo-ai-lisp:*case-root* root)
               (cases (photo-ai-lisp:scan-cases)))
          (is (= 2 (length cases))
              "two subdirs -> two PHOTO-CASE entries")
          (is (every (lambda (c)
                       (typep c 'photo-ai-lisp:photo-case))
                     cases)
              "each entry must be a PHOTO-CASE"))
      (uiop:delete-directory-tree root :validate t))))

;;; ========================================================================
;;; case-id + case-from-id roundtrip
;;; ========================================================================

(test business-ui-case-id-stable
  (let* ((c (photo-ai-lisp:make-photo-case
             :path #P"C:/tmp/spec-ui-case-stable/"
             :name "StableCase")))
    (let ((id1 (photo-ai-lisp:case-id c))
          (id2 (photo-ai-lisp:case-id c)))
      (is (stringp id1) "case-id returns a string")
      (is (equal id1 id2) "same CASE -> same id across calls")
      (is (plusp (length id1)) "id is non-empty")
      (is (every (lambda (ch)
                   (or (alphanumericp ch)
                       (member ch '(#\- #\_))))
                 id1)
          "id must be URL-safe ([a-z0-9-_]): got ~s" id1))))

(test business-ui-case-from-id-roundtrip
  (let ((root (%fresh-case-root)))
    (ensure-directories-exist root)
    (ensure-directories-exist
     (uiop:ensure-directory-pathname (merge-pathnames "alpha/" root)))
    (unwind-protect
        (let* ((photo-ai-lisp:*case-root* root)
               (orig (first (photo-ai-lisp:scan-cases))))
          (is-true orig)
          (let* ((id    (photo-ai-lisp:case-id orig))
                 (again (photo-ai-lisp:case-from-id id)))
            (is-true again
                     "case-from-id must find the case by its own id")
            (is (uiop:pathname-equal (photo-ai-lisp:photo-case-path orig)
                                     (photo-ai-lisp:photo-case-path again))
                "roundtrip: id -> case -> same path")))
      (uiop:delete-directory-tree root :validate t))))

;;; ========================================================================
;;; HTTP handlers
;;; ========================================================================

(test business-ui-list-cases-handler-returns-json
  (let ((root (%fresh-case-root))
        (hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (ensure-directories-exist root)
    (ensure-directories-exist
     (uiop:ensure-directory-pathname (merge-pathnames "job-01/" root)))
    (unwind-protect
        (let* ((photo-ai-lisp:*case-root* root)
               (body (photo-ai-lisp:list-cases-handler)))
          (is (stringp body) "handler returns a string body")
          (is (search "job-01" body)
              "JSON must include the case name/id for job-01")
          (is (or (search "\"id\"" body) (search "\"name\"" body))
              "JSON must carry keyed fields"))
      (uiop:delete-directory-tree root :validate t))))

(test business-ui-case-view-handler-embeds-shell
  (let ((root (%fresh-case-root))
        (hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (ensure-directories-exist root)
    (ensure-directories-exist
     (uiop:ensure-directory-pathname (merge-pathnames "beta/" root)))
    (unwind-protect
        (let* ((photo-ai-lisp:*case-root* root)
               (the-case (first (photo-ai-lisp:scan-cases)))
               (id       (photo-ai-lisp:case-id the-case))
               (html     (photo-ai-lisp:case-view-handler id)))
          (is (stringp html) "handler returns an HTML string")
          (is (search "<!DOCTYPE" html)
              "handler body must be a full HTML document")
          (is (or (search "iframe" html)
                  (search "<iframe" html))
              "case view must embed /shell via iframe")
          (is (search "/shell?case=" html)
              "iframe src must point at /shell with case= query")
          (is (search "beta" html)
              "case view must display the case name somewhere"))
      (uiop:delete-directory-tree root :validate t))))

(test business-ui-case-view-missing-returns-error
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply))
        (photo-ai-lisp:*case-root* (%fresh-case-root)))
    (ensure-directories-exist photo-ai-lisp:*case-root*)
    (unwind-protect
        (let ((body (photo-ai-lisp:case-view-handler "no-such-case-id")))
          (is (stringp body))
          (is (or (search "not found" body)
                  (search "Not Found" body)
                  (search "unknown" body)
                  (search "error" body)
                  (search "Error" body))
              "unknown id -> body must mention error/not found"))
      (uiop:delete-directory-tree photo-ai-lisp:*case-root* :validate t))))

(test business-ui-home-handler-renders-case-list
  (let ((root (%fresh-case-root))
        (hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (ensure-directories-exist root)
    (ensure-directories-exist
     (uiop:ensure-directory-pathname (merge-pathnames "gamma/" root)))
    (unwind-protect
        (let* ((photo-ai-lisp:*case-root* root)
               (body (photo-ai-lisp:home-handler)))
          (is (stringp body))
          ;; Accept either a redirect body (may mention /cases) or an
          ;; inline rendered list (must mention the case name).
          (is (or (search "/cases" body)
                  (search "gamma" body))
              "home handler must route to /cases or show the list inline"))
      (uiop:delete-directory-tree root :validate t))))
