(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(defmacro with-clean-storage (&body body)
  `(let ((photo-ai-lisp::*photos* '())
         (photo-ai-lisp::*next-id* 1))
     ,@body))

(test add-photo-returns-id
  (with-clean-storage
    (let ((id (add-photo "/img/a.jpg")))
      (is (integerp id))
      (is (= 1 id)))))

(test add-photo-increments-id
  (with-clean-storage
    (let ((id1 (add-photo "/img/a.jpg"))
          (id2 (add-photo "/img/b.jpg")))
      (is (= 1 id1))
      (is (= 2 id2)))))

(test all-photos-returns-copy
  (with-clean-storage
    (add-photo "/img/a.jpg")
    (let ((lst (all-photos)))
      (push nil lst)
      (is (= 1 (length (all-photos)))))))

(test find-photo-nil-for-missing
  (with-clean-storage
    (is (null (find-photo 99)))))

(test find-photo-returns-struct
  (with-clean-storage
    (let ((id (add-photo "/img/c.jpg")))
      (let ((p (find-photo id)))
        (is (not (null p)))
        (is (string= "/img/c.jpg" (photo-path p)))))))

(test set-photo-category-updates
  (with-clean-storage
    (let ((id (add-photo "/img/d.jpg")))
      (let ((p (set-photo-category id :after)))
        (is (eql :after (photo-category p)))
        (is (eql :after (photo-category (find-photo id))))))))

(test save-load-roundtrip
  (with-clean-storage
    (uiop:with-temporary-file (:pathname tmp :type "store" :keep nil)
      (let ((photo-ai-lisp::*store-path* tmp))
        (add-photo "/img/e.jpg")
        (save-photos)
        (setf photo-ai-lisp::*photos* '())
        (load-photos)
        (is (= 1 (length (all-photos))))
        (is (string= "/img/e.jpg" (photo-path (first (all-photos)))))))))
