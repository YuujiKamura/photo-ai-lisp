(in-package #:photo-ai-lisp)

(defvar *photos* '())
(defvar *next-id* 1)
(defvar *store-path* (merge-pathnames ".photo-ai-lisp/photos.store" (user-homedir-pathname)))

(defun save-photos ()
  (ensure-directories-exist *store-path*)
  (cl-store:store *photos* *store-path*))

(defun load-photos ()
  (when (probe-file *store-path*)
    (setf *photos* (cl-store:restore *store-path*))))

(defun add-photo (path &optional (category :unclassified))
  (let ((photo (make-photo :id *next-id* :path path :category category)))
    (incf *next-id*)
    (push photo *photos*)
    (save-photos)
    (photo-id photo)))

(defun all-photos ()
  (copy-list *photos*))

(defun find-photo (id)
  (find id *photos* :key #'photo-id))

(defun set-photo-category (id category)
  (let ((photo (find-photo id)))
    (when photo
      (setf (photo-category photo) category)
      (save-photos))
    photo))
