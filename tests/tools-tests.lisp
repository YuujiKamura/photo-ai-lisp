(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test tool-by-name-finds-builtins
  (dolist (name '("scan_photos" "run_pipeline" "list_photos" "export_pdf" "eval_lisp"))
    (is-true (photo-ai-lisp::tool-by-name name)
             "tool-by-name should find ~A" name)))

(test tool-by-name-missing
  (is (null (photo-ai-lisp::tool-by-name "no_such_tool"))))

(test tools-schema-json-structure
  (let* ((schema (photo-ai-lisp::tools-schema-json))
         (parsed (yason:parse schema)))
    (is (listp parsed))
    (is (= 5 (length parsed)))
    (let ((entry (first parsed)))
      (is (hash-table-p entry))
      (is (stringp (gethash "name"        entry)))
      (is (stringp (gethash "description" entry)))
      (is (hash-table-p (gethash "params"  entry))))))

(test dispatch-tool-unknown-returns-error
  (let* ((json "{\"tool\":\"no_such_tool\",\"args\":{}}")
         (result (yason:parse (photo-ai-lisp::dispatch-tool json))))
    (is (eq 'yason:false (or (gethash "ok" result) 'yason:false))
        "dispatch-tool on unknown name must not report ok:true")
    (is (null (gethash "ok" result)))
    (is (stringp (gethash "error" result)))
    (is (search "unknown tool" (gethash "error" result)))))

(test dispatch-tool-missing-tool-field
  (let* ((json "{\"args\":{}}")
         (result (yason:parse (photo-ai-lisp::dispatch-tool json))))
    (is (null (gethash "ok" result)))
    (is (search "missing" (gethash "error" result)))))

(test dispatch-tool-list-photos-round-trip
  (let* ((json "{\"tool\":\"list_photos\",\"args\":{}}")
         (result (yason:parse (photo-ai-lisp::dispatch-tool json))))
    (is (eq t (gethash "ok" result)))
    (is (stringp (gethash "result" result)))))

(test dispatch-tool-eval-lisp-round-trip
  (let* ((json "{\"tool\":\"eval_lisp\",\"args\":{\"form_string\":\"(+ 1 2)\"}}")
         (result (yason:parse (photo-ai-lisp::dispatch-tool json))))
    (is (eq t (gethash "ok" result)))
    (is (search "3" (gethash "result" result)))))

(test dispatch-tool-scan-photos-missing-dir
  (let* ((json "{\"tool\":\"scan_photos\",\"args\":{}}")
         (result (yason:parse (photo-ai-lisp::dispatch-tool json))))
    (is (null (gethash "ok" result)))
    (is (search "dir" (gethash "error" result)))))

(test dispatch-tool-parse-failure
  (let* ((json "{not json")
         (result (yason:parse (photo-ai-lisp::dispatch-tool json))))
    (is (null (gethash "ok" result)))
    (is (stringp (gethash "error" result)))))
