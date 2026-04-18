(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test layout-returns-string
  (let ((html (layout "Test Title" (:p "hello"))))
    (is (stringp html))
    (is (> (length html) 0))))

(test layout-contains-title
  (let ((html (layout "My Page" (:p "content"))))
    (is (search "My Page" html))))

(test layout-contains-doctype
  (let ((html (layout "X" (:p "y"))))
    (is (search "DOCTYPE" html))))
