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

;;; --- 5c: cursor model ---

(test screen-cursor-starts-at-origin
  (let* ((s (photo-ai-lisp:make-screen 3 5))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (is (= 0 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))))

(test cursor-move-relative
  (let* ((s (photo-ai-lisp:make-screen 4 6))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (photo-ai-lisp:cursor-move cursor s :rel-row 2 :rel-col 3)
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 3 (photo-ai-lisp:cursor-col cursor)))))

(test cursor-move-clamps-at-screen-edges
  (let* ((s (photo-ai-lisp:make-screen 3 4))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (photo-ai-lisp:cursor-move cursor s :rel-row -2 :rel-col -5)
    (is (= 0 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:cursor-move cursor s :rel-row 20 :rel-col 20)
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 3 (photo-ai-lisp:cursor-col cursor)))))

;;; --- 5d: scrollback ---

(test screen-scroll-up-shifts-and-blanks
  (let* ((s (photo-ai-lisp:make-screen 3 2))
         (buf (photo-ai-lisp:screen-buffer s)))
    (setf (photo-ai-lisp:cell-char (aref buf 0 0)) #\A
          (photo-ai-lisp:cell-char (aref buf 0 1)) #\B
          (photo-ai-lisp:cell-char (aref buf 1 0)) #\C
          (photo-ai-lisp:cell-char (aref buf 1 1)) #\D
          (photo-ai-lisp:cell-char (aref buf 2 0)) #\E
          (photo-ai-lisp:cell-char (aref buf 2 1)) #\F)
    (photo-ai-lisp:screen-scroll-up s)
    (is (char= #\C (photo-ai-lisp:cell-char (aref buf 0 0))))
    (is (char= #\D (photo-ai-lisp:cell-char (aref buf 0 1))))
    (is (char= #\E (photo-ai-lisp:cell-char (aref buf 1 0))))
    (is (char= #\F (photo-ai-lisp:cell-char (aref buf 1 1))))
    (is (char= #\Space (photo-ai-lisp:cell-char (aref buf 2 0))))
    (is (char= #\Space (photo-ai-lisp:cell-char (aref buf 2 1))))))

(test screen-scroll-up-saves-top-row-copy
  (let* ((s (photo-ai-lisp:make-screen 2 2))
         (buf (photo-ai-lisp:screen-buffer s)))
    (setf (photo-ai-lisp:cell-char (aref buf 0 0)) #\X
          (photo-ai-lisp:cell-char (aref buf 0 1)) #\Y)
    (photo-ai-lisp:screen-scroll-up s)
    (is (= 1 (length (photo-ai-lisp:screen-scrollback s))))
    (is (char= #\X (photo-ai-lisp:cell-char (aref (first (photo-ai-lisp:screen-scrollback s)) 0))))
    (is (char= #\Y (photo-ai-lisp:cell-char (aref (first (photo-ai-lisp:screen-scrollback s)) 1))))
    (setf (photo-ai-lisp:cell-char (aref buf 0 0)) #\Z)
    (is (char= #\X (photo-ai-lisp:cell-char (aref (first (photo-ai-lisp:screen-scrollback s)) 0))))))

(test screen-scroll-up-caps-scrollback-at-1000
  (let ((s (photo-ai-lisp:make-screen 1 1)))
    (dotimes (n 1005)
      (setf (photo-ai-lisp:cell-char (aref (photo-ai-lisp:screen-buffer s) 0 0))
            (code-char (+ 65 (mod n 26))))
      (photo-ai-lisp:screen-scroll-up s))
    (is (= 1000 (length (photo-ai-lisp:screen-scrollback s))))))

;;; --- 5e.1: event dispatch + print ---

(test apply-event-print-writes-cell-and-advances-cursor
  (let* ((s (photo-ai-lisp:make-screen 2 3))
         (cursor (photo-ai-lisp:screen-cursor s))
         (cell (photo-ai-lisp:make-cell :fg 2 :bg 4 :bold t)))
    (setf (photo-ai-lisp:cursor-attrs cursor) cell)
    (photo-ai-lisp:apply-event s '(:type :print :char #\Q))
    (let ((written (aref (photo-ai-lisp:screen-buffer s) 0 0)))
      (is (char= #\Q (photo-ai-lisp:cell-char written)))
      (is (= 2 (photo-ai-lisp:cell-fg written)))
      (is (= 4 (photo-ai-lisp:cell-bg written)))
      (is (eq t (photo-ai-lisp:cell-bold written))))
    (is (= 0 (photo-ai-lisp:cursor-row cursor)))
    (is (= 1 (photo-ai-lisp:cursor-col cursor)))))

(test apply-event-print-wraps-at-end-of-row
  (let* ((s (photo-ai-lisp:make-screen 2 2))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (setf (photo-ai-lisp:cursor-col cursor) 1)
    (photo-ai-lisp:apply-event s '(:type :print :char #\X))
    (is (char= #\X (photo-ai-lisp:cell-char (aref (photo-ai-lisp:screen-buffer s) 0 1))))
    (is (= 1 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))))

(test apply-event-print-wraps-and-scrolls-from-bottom-right
  (let* ((s (photo-ai-lisp:make-screen 2 2))
         (cursor (photo-ai-lisp:screen-cursor s))
         (buf (photo-ai-lisp:screen-buffer s)))
    (setf (photo-ai-lisp:cell-char (aref buf 0 0)) #\A
          (photo-ai-lisp:cell-char (aref buf 0 1)) #\B
          (photo-ai-lisp:cell-char (aref buf 1 0)) #\C
          (photo-ai-lisp:cursor-row cursor) 1
          (photo-ai-lisp:cursor-col cursor) 1)
    (photo-ai-lisp:apply-event s '(:type :print :char #\Z))
    (is (char= #\C (photo-ai-lisp:cell-char (aref buf 0 0))))
    (is (char= #\Z (photo-ai-lisp:cell-char (aref buf 0 1))))
    (is (char= #\Space (photo-ai-lisp:cell-char (aref buf 1 0))))
    (is (= 1 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))
    (is (= 1 (length (photo-ai-lisp:screen-scrollback s))))))

(test apply-event-cursor-move-up-down-left-right
  (let* ((s (photo-ai-lisp:make-screen 4 5))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (setf (photo-ai-lisp:cursor-row cursor) 1
          (photo-ai-lisp:cursor-col cursor) 1)
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :down :count 2))
    (is (= 3 (photo-ai-lisp:cursor-row cursor)))
    (is (= 1 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :right :count 3))
    (is (= 3 (photo-ai-lisp:cursor-row cursor)))
    (is (= 4 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :up :count 1))
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 4 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :left :count 2))
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 2 (photo-ai-lisp:cursor-col cursor)))))

(test apply-event-cursor-move-clamps-at-screen-edges
  (let* ((s (photo-ai-lisp:make-screen 3 4))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (setf (photo-ai-lisp:cursor-row cursor) 0
          (photo-ai-lisp:cursor-col cursor) 0)
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :up :count 5))
    (is (= 0 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :left :count 5))
    (is (= 0 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :down :count 10))
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:apply-event s '(:type :cursor-move :direction :right :count 10))
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 3 (photo-ai-lisp:cursor-col cursor)))))

(test apply-event-cursor-position-uses-ansi-1-based-coordinates
  (let* ((s (photo-ai-lisp:make-screen 5 6))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (photo-ai-lisp:apply-event s '(:type :cursor-position :row 3 :col 4))
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 3 (photo-ai-lisp:cursor-col cursor)))))

(test apply-event-cursor-position-clamps-out-of-bounds
  (let* ((s (photo-ai-lisp:make-screen 3 4))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (photo-ai-lisp:apply-event s '(:type :cursor-position :row 99 :col 99))
    (is (= 2 (photo-ai-lisp:cursor-row cursor)))
    (is (= 3 (photo-ai-lisp:cursor-col cursor)))
    (photo-ai-lisp:apply-event s '(:type :cursor-position :row 0 :col 0))
    (is (= 0 (photo-ai-lisp:cursor-row cursor)))
    (is (= 0 (photo-ai-lisp:cursor-col cursor)))))

(test apply-event-erase-display-mode-0-clears-from-cursor-through-end
  (let* ((s (photo-ai-lisp:make-screen 3 4))
         (buffer (photo-ai-lisp:screen-buffer s))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (dotimes (row 3)
      (dotimes (col 4)
        (setf (aref buffer row col)
              (photo-ai-lisp:make-cell :char #\X :fg 3 :bg 4 :bold t :underline t :reverse t))))
    (setf (photo-ai-lisp:cursor-row cursor) 1
          (photo-ai-lisp:cursor-col cursor) 2)
    (photo-ai-lisp:apply-event s '(:type :erase-display :mode 0))
    (is (char= #\X (photo-ai-lisp:cell-char (aref buffer 1 1))))
    (is (char= #\Space (photo-ai-lisp:cell-char (aref buffer 1 2))))
    (is (= 7 (photo-ai-lisp:cell-fg (aref buffer 1 2))))
    (is (= 0 (photo-ai-lisp:cell-bg (aref buffer 2 3))))
    (is (null (photo-ai-lisp:cell-bold (aref buffer 2 3))))))

(test apply-event-erase-display-mode-1-clears-start-through-cursor
  (let* ((s (photo-ai-lisp:make-screen 3 4))
         (buffer (photo-ai-lisp:screen-buffer s))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (dotimes (row 3)
      (dotimes (col 4)
        (setf (aref buffer row col)
              (photo-ai-lisp:make-cell :char #\Y :fg 1 :bg 6 :underline t))))
    (setf (photo-ai-lisp:cursor-row cursor) 1
          (photo-ai-lisp:cursor-col cursor) 1)
    (photo-ai-lisp:apply-event s '(:type :erase-display :mode 1))
    (is (char= #\Space (photo-ai-lisp:cell-char (aref buffer 0 0))))
    (is (null (photo-ai-lisp:cell-underline (aref buffer 1 1))))
    (is (char= #\Y (photo-ai-lisp:cell-char (aref buffer 1 2))))
    (is (char= #\Y (photo-ai-lisp:cell-char (aref buffer 2 3))))))

(test apply-event-erase-display-mode-2-clears-entire-screen
  (let* ((s (photo-ai-lisp:make-screen 2 3))
         (buffer (photo-ai-lisp:screen-buffer s)))
    (dotimes (row 2)
      (dotimes (col 3)
        (setf (aref buffer row col)
              (photo-ai-lisp:make-cell :char #\Z :fg 2 :bg 5 :reverse t))))
    (photo-ai-lisp:apply-event s '(:type :erase-display :mode 2))
    (dotimes (row 2)
      (dotimes (col 3)
        (let ((cell (aref buffer row col)))
          (is (char= #\Space (photo-ai-lisp:cell-char cell)))
          (is (= 7 (photo-ai-lisp:cell-fg cell)))
          (is (= 0 (photo-ai-lisp:cell-bg cell)))
          (is (null (photo-ai-lisp:cell-reverse cell))))))))

(test apply-event-erase-line-mode-0-clears-cursor-through-line-end
  (let* ((s (photo-ai-lisp:make-screen 2 5))
         (buffer (photo-ai-lisp:screen-buffer s))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (dotimes (col 5)
      (setf (aref buffer 1 col)
            (photo-ai-lisp:make-cell :char #\L :fg 4 :bg 1 :bold t)))
    (setf (photo-ai-lisp:cursor-row cursor) 1
          (photo-ai-lisp:cursor-col cursor) 2)
    (photo-ai-lisp:apply-event s '(:type :erase-line :mode 0))
    (is (char= #\L (photo-ai-lisp:cell-char (aref buffer 1 1))))
    (is (char= #\Space (photo-ai-lisp:cell-char (aref buffer 1 2))))
    (is (null (photo-ai-lisp:cell-bold (aref buffer 1 4))))))

(test apply-event-erase-line-mode-1-clears-line-start-through-cursor
  (let* ((s (photo-ai-lisp:make-screen 1 5))
         (buffer (photo-ai-lisp:screen-buffer s))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (dotimes (col 5)
      (setf (aref buffer 0 col)
            (photo-ai-lisp:make-cell :char #\M :fg 6 :bg 2 :underline t)))
    (setf (photo-ai-lisp:cursor-col cursor) 3)
    (photo-ai-lisp:apply-event s '(:type :erase-line :mode 1))
    (is (char= #\Space (photo-ai-lisp:cell-char (aref buffer 0 0))))
    (is (null (photo-ai-lisp:cell-underline (aref buffer 0 3))))
    (is (char= #\M (photo-ai-lisp:cell-char (aref buffer 0 4))))))

(test apply-event-erase-line-mode-2-clears-entire-line-only
  (let* ((s (photo-ai-lisp:make-screen 2 4))
         (buffer (photo-ai-lisp:screen-buffer s))
         (cursor (photo-ai-lisp:screen-cursor s)))
    (dotimes (row 2)
      (dotimes (col 4)
        (setf (aref buffer row col)
              (photo-ai-lisp:make-cell :char (if (= row 0) #\A #\B) :fg 5 :bg 3 :reverse t))))
    (setf (photo-ai-lisp:cursor-row cursor) 1)
    (photo-ai-lisp:apply-event s '(:type :erase-line :mode 2))
    (dotimes (col 4)
      (let ((cell (aref buffer 1 col)))
        (is (char= #\Space (photo-ai-lisp:cell-char cell)))
        (is (= 7 (photo-ai-lisp:cell-fg cell)))
        (is (null (photo-ai-lisp:cell-reverse cell)))))
    (is (char= #\A (photo-ai-lisp:cell-char (aref buffer 0 0))))
    (is (char= #\A (photo-ai-lisp:cell-char (aref buffer 0 3))))))

;;; --- 5f: screen snapshot ---

(test screen->text-on-blank-screen
  (let ((s (photo-ai-lisp:make-screen 2 3)))
    (is (string= (format nil "~%") (photo-ai-lisp:screen->text s)))))

(test screen->text-contains-printed-content
  (let ((s (photo-ai-lisp:make-screen 2 4)))
    (photo-ai-lisp:apply-event s '(:type :print :char #\H))
    (photo-ai-lisp:apply-event s '(:type :print :char #\i))
    (is (search "Hi" (photo-ai-lisp:screen->text s)))))
