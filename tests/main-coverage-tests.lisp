(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT6 — coverage gap-fill for src/main.lisp
;;; Covers home-page HTML content (/ easy-handler).

(test main-home-page-returns-html
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (let ((html (photo-ai-lisp::home-page)))
      (is-true (stringp html)
               "home-page should return a string, got: ~s" (type-of html))
      (is-true (search "<html" html)
               "home-page HTML should contain an <html tag, got: ~s"
               (subseq html 0 (min 200 (length html)))))))

(test main-home-page-links-to-term
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (let ((html (photo-ai-lisp::home-page)))
      (is-true (search "/term" html)
               "home-page should link to /term, got: ~s"
               (subseq html 0 (min 300 (length html)))))))

(test main-home-page-has-title
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (let ((html (photo-ai-lisp::home-page)))
      (is-true (search "photo-ai-lisp" html)
               "home-page HTML should contain the project title"))))
