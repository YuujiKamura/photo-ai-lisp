(in-package #:photo-ai-lisp/tests)

(def-suite screen-tests
  :in photo-ai-lisp-tests
  :description "Tests for screen buffer")

(in-suite screen-tests)

;;; --- 5a: cell ---

(test cell-defaults
  (let ((c (photo-ai-lisp:make-cell)))
    (is (char= #\Space (photo-ai-lisp:cell-char c)))
    (is (= 7 (photo-ai-lisp:cell-fg c)))
    (is (= 0 (photo-ai-lisp:cell-bg c)))
    (is (null (photo-ai-lisp:cell-bold c)))
    (is (null (photo-ai-lisp:cell-underline c)))))

(test cell-copy
  (let* ((c (photo-ai-lisp:make-cell :char #\A :fg 1 :bg 2 :bold t))
         (c2 (photo-ai-lisp:copy-cell c)))
    (is (char= #\A (photo-ai-lisp:cell-char c2)))
    (is (= 1 (photo-ai-lisp:cell-fg c2)))
    (is (= 2 (photo-ai-lisp:cell-bg c2)))
    (is (eq t (photo-ai-lisp:cell-bold c2)))))

(test cell-equal
  (let ((c1 (photo-ai-lisp:make-cell :char #\X :fg 3))
        (c2 (photo-ai-lisp:make-cell :char #\X :fg 3)))
    (is (equalp c1 c2))
    (is (not (equalp c1 (photo-ai-lisp:make-cell :char #\Y :fg 3))))))

;;; --- 5b: screen grid ---

(test screen-make-dimensions
  (let ((s (photo-ai-lisp:make-screen 3 5)))
    (is (= 3 (photo-ai-lisp:screen-rows s)))
    (is (= 5 (photo-ai-lisp:screen-cols s)))))

(test screen-buffer-array-shape
  (let* ((s   (photo-ai-lisp:make-screen 4 10))
         (buf (photo-ai-lisp:screen-buffer s)))
    (is (= 4  (array-dimension buf 0)))
    (is (= 10 (array-dimension buf 1)))))

(test screen-buffer-filled-with-default-cells
  (let ((s (photo-ai-lisp:make-screen 2 3)))
    (dotimes (r 2)
      (dotimes (c 3)
        (let ((cell (aref (photo-ai-lisp:screen-buffer s) r c)))
          (is (char= #\Space (photo-ai-lisp:cell-char cell)))
          (is (= 7 (photo-ai-lisp:cell-fg cell)))
          (is (= 0 (photo-ai-lisp:cell-bg cell))))))))
