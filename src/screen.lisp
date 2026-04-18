(in-package #:photo-ai-lisp)

;;; --- 5a: Cell ---

(defstruct cell
  (char #\Space :type character)
  (fg 7 :type fixnum)
  (bg 0 :type fixnum)
  (bold nil)
  (underline nil)
  (reverse nil))
