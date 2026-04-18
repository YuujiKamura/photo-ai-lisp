(in-package #:photo-ai-lisp)

(defvar *photos* '())
(defvar *next-id* 1)

(defun add-photo (path &optional (category :unclassified))
  (let ((photo (make-photo :id *next-id* :path path :category category)))
    (incf *next-id*)
    (push photo *photos*)
    (photo-id photo)))

(defun all-photos ()
  (copy-list *photos*))

(defun find-photo (id)
  (find id *photos* :key #'photo-id))

(defun set-photo-category (id category)
  (let ((photo (find-photo id)))
    (when photo
      (setf (photo-category photo) category))
    photo))
