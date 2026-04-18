(in-package #:photo-ai-lisp/tests)

(def-suite ansi-tests
  :in photo-ai-lisp-tests
  :description "Tests for ANSI parser")

(in-suite ansi-tests)

(test printable-chars
  (let ((p (photo-ai-lisp:make-parser)))
    (is (equal '((:type :print :char #\A)) (photo-ai-lisp:parser-feed-string p "A")))
    (is (equal '((:type :print :char #\B) (:type :print :char #\C)) (photo-ai-lisp:parser-feed-string p "BC")))
    (is (equal '((:type :print :char #\Space)) (photo-ai-lisp:parser-feed-string p " ")))
    (is (equal '((:type :print :char #\a) (:type :print :char #\z)) (photo-ai-lisp:parser-feed-string p "az")))))

(test simple-controls
  (let ((p (photo-ai-lisp:make-parser)))
    (is (equal '((:type :bell)) (photo-ai-lisp:parser-feed p #x07)))
    (is (equal '((:type :bs)) (photo-ai-lisp:parser-feed p #x08)))
    (is (equal '((:type :ht)) (photo-ai-lisp:parser-feed p #x09)))
    (is (equal '((:type :lf)) (photo-ai-lisp:parser-feed p #x0a)))
    (is (equal '((:type :cr)) (photo-ai-lisp:parser-feed p #x0d)))))

(test csi-cursor-move
  (let ((p (photo-ai-lisp:make-parser)))
    ;; CUU - Up
    (is (equal '((:type :cursor-move :direction :up :count 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[A" #\Esc))))
    (is (equal '((:type :cursor-move :direction :up :count 5)) (photo-ai-lisp:parser-feed-string p (format nil "~C[5A" #\Esc))))
    ;; CUD - Down
    (is (equal '((:type :cursor-move :direction :down :count 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[B" #\Esc))))
    (is (equal '((:type :cursor-move :direction :down :count 10)) (photo-ai-lisp:parser-feed-string p (format nil "~C[10B" #\Esc))))
    ;; CUF - Right
    (is (equal '((:type :cursor-move :direction :right :count 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[C" #\Esc))))
    (is (equal '((:type :cursor-move :direction :right :count 2)) (photo-ai-lisp:parser-feed-string p (format nil "~C[2C" #\Esc))))
    ;; CUB - Left
    (is (equal '((:type :cursor-move :direction :left :count 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[D" #\Esc))))
    (is (equal '((:type :cursor-move :direction :left :count 3)) (photo-ai-lisp:parser-feed-string p (format nil "~C[3D" #\Esc))))))

(test csi-cursor-position
  (let ((p (photo-ai-lisp:make-parser)))
    (is (equal '((:type :cursor-position :row 1 :col 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[H" #\Esc))))
    (is (equal '((:type :cursor-position :row 10 :col 20)) (photo-ai-lisp:parser-feed-string p (format nil "~C[10;20H" #\Esc))))
    (is (equal '((:type :cursor-position :row 5 :col 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[5;H" #\Esc))))
    (is (equal '((:type :cursor-position :row 1 :col 8)) (photo-ai-lisp:parser-feed-string p (format nil "~C[;8H" #\Esc))))))

(test csi-erase
  (let ((p (photo-ai-lisp:make-parser)))
    ;; Erase Display
    (is (equal '((:type :erase-display :mode 0)) (photo-ai-lisp:parser-feed-string p (format nil "~C[J" #\Esc))))
    (is (equal '((:type :erase-display :mode 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[1J" #\Esc))))
    (is (equal '((:type :erase-display :mode 2)) (photo-ai-lisp:parser-feed-string p (format nil "~C[2J" #\Esc))))
    ;; Erase Line
    (is (equal '((:type :erase-line :mode 0)) (photo-ai-lisp:parser-feed-string p (format nil "~C[K" #\Esc))))
    (is (equal '((:type :erase-line :mode 1)) (photo-ai-lisp:parser-feed-string p (format nil "~C[1K" #\Esc))))
    (is (equal '((:type :erase-line :mode 2)) (photo-ai-lisp:parser-feed-string p (format nil "~C[2K" #\Esc))))))

(test csi-sgr
  (let ((p (photo-ai-lisp:make-parser)))
    (is (equal '((:type :set-attr :attrs (0))) (photo-ai-lisp:parser-feed-string p (format nil "~C[m" #\Esc))))
    (is (equal '((:type :set-attr :attrs (1))) (photo-ai-lisp:parser-feed-string p (format nil "~C[1m" #\Esc))))
    (is (equal '((:type :set-attr :attrs (31 42))) (photo-ai-lisp:parser-feed-string p (format nil "~C[31;42m" #\Esc))))
    (is (equal '((:type :set-attr :attrs (0 1 4 33 44))) (photo-ai-lisp:parser-feed-string p (format nil "~C[0;1;4;33;44m" #\Esc))))))

(test osc-title
  (let ((p (photo-ai-lisp:make-parser)))
    (is (equal '((:type :set-title :title "Hello")) (photo-ai-lisp:parser-feed-string p (format nil "~C]0;Hello~C" #\Esc #\Bel))))
    (is (equal '((:type :set-title :title "World")) (photo-ai-lisp:parser-feed-string p (format nil "~C]2;World~C\\" #\Esc #\Esc))))))

(test mixed-sequences
  (let ((p (photo-ai-lisp:make-parser)))
    (let ((events (photo-ai-lisp:parser-feed-string p (format nil "A~C[31mB~C[mC" #\Esc #\Esc))))
      (is (equal '((:type :print :char #\A)
                   (:type :set-attr :attrs (31))
                   (:type :print :char #\B)
                   (:type :set-attr :attrs (0))
                   (:type :print :char #\C))
                 events)))))

(test unknown-sequences
  (let ((p (photo-ai-lisp:make-parser)))
    ;; Unknown CSI
    (let ((events (photo-ai-lisp:parser-feed-string p (format nil "~C[?123h" #\Esc))))
      (is (eq :unknown (getf (first events) :type))))
    ;; Unknown Escape
    (let ((events (photo-ai-lisp:parser-feed-string p (format nil "~CX" #\Esc))))
      (is (eq :unknown (getf (first events) :type))))))
