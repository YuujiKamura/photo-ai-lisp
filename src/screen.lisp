(in-package #:photo-ai-lisp)

;;; --- 5a: Cell ---

(defstruct cell
  (char #\Space :type character)
  (fg 7 :type fixnum)
  (bg 0 :type fixnum)
  (bold nil)
  (underline nil)
  (reverse nil))

;;; --- 5b: Screen grid ---

(defclass screen ()
  ((rows   :initarg :rows   :reader screen-rows)
   (cols   :initarg :cols   :reader screen-cols)
   (buffer :accessor screen-buffer)
   (cursor :initform nil    :accessor screen-cursor)))

(defun make-screen (rows cols)
  "Create a ROWS×COLS screen buffer filled with default cells."
  (let ((s   (make-instance 'screen :rows rows :cols cols))
        (buf (make-array (list rows cols))))
    (dotimes (r rows)
      (dotimes (c cols)
        (setf (aref buf r c) (make-cell))))
    (setf (screen-buffer s) buf)
    s))
