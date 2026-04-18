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
