(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test make-photo-defaults
  (let ((p (make-photo :id 1 :path "/a/b.jpg")))
    (is (= 1 (photo-id p)))
    (is (string= "/a/b.jpg" (photo-path p)))
    (is (eql :unclassified (photo-category p)))
    (is (integerp (photo-uploaded-at p)))))

(test photo-slot-writable
  (let ((p (make-photo :id 1 :path "/x.jpg")))
    (setf (photo-category p) :before)
    (is (eql :before (photo-category p)))))
