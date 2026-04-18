(in-package #:photo-ai-lisp)

;;; --- 5a: Cell ---

(defstruct cell
  (char #\Space :type character)
  (fg 7 :type fixnum)
  (bg 0 :type fixnum)
  (bold nil)
  (underline nil)
  (reverse nil))

(defstruct (cursor (:constructor %make-cursor))
  (row 0 :type fixnum)
  (col 0 :type fixnum)
  (visible t)
  (attrs nil))

(defun make-cursor ()
  (%make-cursor :attrs (make-cell)))

;;; --- 5b: Screen grid ---

(defclass screen ()
  ((rows   :initarg :rows   :reader screen-rows)
   (cols   :initarg :cols   :reader screen-cols)
   (buffer :accessor screen-buffer)
   (cursor :initform nil    :accessor screen-cursor)
   (scrollback :initform nil :accessor screen-scrollback)))

(defun cursor-move (cursor screen &key (rel-row 0) (rel-col 0))
  (setf (cursor-row cursor)
        (min (1- (screen-rows screen))
             (max 0 (+ (cursor-row cursor) rel-row)))
        (cursor-col cursor)
        (min (1- (screen-cols screen))
             (max 0 (+ (cursor-col cursor) rel-col))))
  cursor)

(defun screen-scroll-up (screen)
  (let* ((rows (screen-rows screen))
         (cols (screen-cols screen))
         (buffer (screen-buffer screen))
         (top-row (make-array cols)))
    (dotimes (col cols)
      (setf (aref top-row col) (copy-cell (aref buffer 0 col))))
    (setf (screen-scrollback screen)
          (subseq (cons top-row (screen-scrollback screen))
                  0
                  (min 1000 (1+ (length (screen-scrollback screen))))))
    (dotimes (row (1- rows))
      (dotimes (col cols)
        (setf (aref buffer row col)
              (copy-cell (aref buffer (1+ row) col)))))
    (dotimes (col cols)
      (setf (aref buffer (1- rows) col) (make-cell)))
    screen))

(defun make-screen (rows cols)
  "Create a ROWS×COLS screen buffer filled with default cells."
  (let ((s   (make-instance 'screen :rows rows :cols cols))
        (buf (make-array (list rows cols))))
    (dotimes (r rows)
      (dotimes (c cols)
        (setf (aref buf r c) (make-cell))))
    (setf (screen-buffer s) buf
          (screen-cursor s) (make-cursor))
    s))
