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
   (cursor :initform nil    :accessor screen-cursor)))

(defun cursor-move (cursor screen &key (rel-row 0) (rel-col 0))
  (setf (cursor-row cursor)
        (min (1- (screen-rows screen))
             (max 0 (+ (cursor-row cursor) rel-row)))
        (cursor-col cursor)
        (min (1- (screen-cols screen))
             (max 0 (+ (cursor-col cursor) rel-col))))
  cursor)

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
