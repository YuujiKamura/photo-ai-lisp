(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test parse-category-known
  (is (eql :before        (photo-ai-lisp::parse-category "before")))
  (is (eql :after         (photo-ai-lisp::parse-category "after")))
  (is (eql :note          (photo-ai-lisp::parse-category "note"))))

(test parse-category-unknown
  (is (eql :unclassified  (photo-ai-lisp::parse-category "bogus")))
  (is (eql :unclassified  (photo-ai-lisp::parse-category nil)))
  (is (eql :unclassified  (photo-ai-lisp::parse-category ""))))

(test parse-int-valid
  (is (= 42 (photo-ai-lisp::parse-int "42"))))

(test parse-int-invalid
  (is (null (photo-ai-lisp::parse-int "abc"))))

(test parse-and-eval-expr-success
  (let ((r (photo-ai-lisp::parse-and-eval-expr "(+ 1 2)")))
    (is-true (getf r :ok))
    (is (string= "3" (getf r :value)))
    (is (string= "" (getf r :stdout)))))

(test parse-and-eval-expr-error
  (let ((r (photo-ai-lisp::parse-and-eval-expr "(/ 1 0)")))
    (is-false (getf r :ok))
    (is (stringp (getf r :error)))
    (is (plusp (length (getf r :error))))))

(test parse-and-eval-expr-stdout
  (let ((r (photo-ai-lisp::parse-and-eval-expr "(progn (format t \"hi\") 7)")))
    (is-true (getf r :ok))
    (is (string= "7"  (getf r :value)))
    (is (string= "hi" (getf r :stdout)))))

(test parse-and-eval-expr-read-error
  (let ((r (photo-ai-lisp::parse-and-eval-expr "(unbalanced")))
    (is-false (getf r :ok))
    (is (stringp (getf r :error)))))
