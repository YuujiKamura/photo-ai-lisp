;;; Startup:
;;;   (ql:quickload :photo-ai-lisp)
;;;   (photo-ai-lisp:start)

(in-package #:photo-ai-lisp)

(defvar *acceptor* nil)

(defparameter *categories* '(:unclassified :before :after :note))

(defun parse-int (value)
  (ignore-errors (parse-integer value)))

(defun parse-category (value)
  (let ((normalized (and value (string-downcase value))))
    (cond ((string= normalized "before") :before)
          ((string= normalized "after") :after)
          ((string= normalized "note") :note)
          (t :unclassified))))

(defun request-path ()
  (script-name*))

(defun photo-id-from-path ()
  (let* ((path (request-path))
         (start (length "/photo/"))
         (end (or (position #\/ path :start start) (length path))))
    (and (< start end) (parse-int (subseq path start end)))))

(defun render-category-options (selected)
  (loop for category in *categories* do
    (htm
     (:option :value (string-downcase (symbol-name category))
      :selected (when (eql selected category) "selected")
      (str (string-downcase (symbol-name category)))))))

(defun index-page ()
  (layout "photo-ai-lisp"
    (:table :border "1" :cellpadding "6"
     (:tr (:th "ID") (:th "Path") (:th "Category") (:th "Uploaded") (:th "Link"))
     (dolist (photo (reverse (all-photos)))
       (htm
        (:tr
         (:td (str (photo-id photo)))
         (:td (str (photo-path photo)))
         (:td (str (string-downcase (symbol-name (photo-category photo)))))
         (:td (str (photo-uploaded-at photo)))
         (:td (:a :href (format nil "/photo/~D" (photo-id photo)) "Open"))))))))

(defun upload-page ()
  (layout "Upload"
    (:form :action "/upload" :method "POST" :enctype "multipart/form-data"
     (:p "Path" (:br) (:input :type "text" :name "path"))
     (:p "Category" (:br)
      (:select :name "category" (render-category-options :unclassified)))
     (:p (:input :type "submit" :value "Save")))))

(defun photo-page (photo)
  (layout "Photo"
    (:h2 (str (format nil "Photo ~D" (photo-id photo))))
    (:p "Path: " (str (photo-path photo)))
    (:p "Uploaded: " (str (photo-uploaded-at photo)))
    (:form :action (format nil "/photo/~D/category" (photo-id photo)) :method "POST"
     (:p "Category" (:br)
      (:select :name "category" (render-category-options (photo-category photo))))
     (:p (:input :type "submit" :value "Update")))))

(defun pipeline-page ()
  (layout "Pipeline"
    (:h2 "Full pipeline")
    (:form :action "/pipeline/run" :method "POST"
     (:p "Photo directory" (:br) (:input :type "text" :name "dir" :size "60"))
     (:p (:input :type "submit" :value "Run pipeline")))
    (:div :id "status" (:p "No pipeline run yet."))
    (:script
     (str "var poll=setInterval(function(){fetch('/pipeline/status').then(r=>r.json()).then(function(steps){var h='<table border=1 cellpadding=4><tr><th>Step</th><th>Status</th><th>Info</th></tr>';steps.forEach(function(s){h+='<tr><td>'+s.name+'</td><td>'+s.status+'</td><td>'+(s.artifact||s.error||'')+'</td></tr>';});h+='</table>';document.getElementById('status').innerHTML=h;if(steps.every(function(s){return s.status==='done'||s.status==='failed';}))clearInterval(poll);});},2000);"))))

(defun pipeline-status ()
  (setf (content-type*) "application/json")
  (with-output-to-string (s)
    (yason:encode
     (mapcar (lambda (step)
               (let ((h (make-hash-table :test 'equal)))
                 (setf (gethash "name"     h) (getf step :name)
                       (gethash "status"   h) (string-downcase (symbol-name (getf step :status)))
                       (gethash "artifact" h) (or (getf step :artifact) "")
                       (gethash "error"    h) (or (getf step :error) ""))
                 h))
             (or *pipeline-state* '()))
     s)))

(defun pipeline-run-dispatch ()
  (if (eq (request-method*) :POST)
      (let ((dir (post-parameter "dir")))
        (run-pipeline dir)
        (redirect "/pipeline"))
      (progn (setf (return-code*) 405) "Method Not Allowed")))

(defun scan-page ()
  (layout "Scan"
    (:h2 "Scan photo directory")
    (:form :action "/scan" :method "POST"
     (:p "Directory path" (:br) (:input :type "text" :name "dir" :size "60"))
     (:p (:input :type "submit" :value "Scan")))))

(defun manifest-page ()
  (layout "Manifest"
    (:h2 "Photo manifest")
    (if *current-manifest*
        (htm
         (:p (str (format nil "~A photos" (length *current-manifest*))))
         (:table :border "1" :cellpadding "4"
          (:tr (:th "File") (:th "Dir") (:th "Date") (:th "OCR preview"))
          (dolist (rec *current-manifest*)
            (let ((ocr (or (gethash "ocr_text" rec) "")))
              (htm (:tr
                    (:td (str (gethash "file_name" rec "")))
                    (:td (str (gethash "dir_name" rec "")))
                    (:td (str (gethash "date" rec "")))
                    (:td (str (if (> (length ocr) 60)
                                  (subseq ocr 0 60)
                                  ocr)))))))))
        (htm (:p "No manifest loaded. Run a scan first.")))))

(defun scan-dispatch ()
  (cond
    ((eq (request-method*) :GET) (scan-page))
    ((eq (request-method*) :POST)
     (let ((dir (post-parameter "dir")))
       (handler-case
           (progn
             (setf *current-manifest* (run-skill "photo-scan" dir))
             (redirect "/manifest"))
         (skill-error (e)
           (layout "Scan error"
             (:h2 "Scan failed")
             (:pre (str (skill-error-stderr e))))))))
    (t (setf (return-code*) 405) "Method Not Allowed")))

(defun upload-dispatch ()
  (cond ((eq (request-method*) :GET) (upload-page))
        ((eq (request-method*) :POST)
         (add-photo (or (post-parameter "path") "")
                    (parse-category (post-parameter "category")))
         (redirect "/"))
        (t (setf (return-code*) 405) "Method Not Allowed")))

(defun photo-dispatch ()
  (let* ((id (photo-id-from-path))
         (photo (and id (find-photo id))))
    (cond ((null photo) (setf (return-code*) 404) "Not Found")
          ((and (eq (request-method*) :GET)
                (search "/category" (request-path))) (setf (return-code*) 405) "Method Not Allowed")
          ((eq (request-method*) :GET) (photo-page photo))
          ((and (eq (request-method*) :POST)
                (search "/category" (request-path)))
           (set-photo-category (photo-id photo)
                               (parse-category (post-parameter "category")))
           (redirect "/"))
          (t (setf (return-code*) 405) "Method Not Allowed"))))

(defun start (&key (port 8080))
  (unless *acceptor*
    (load-photos)
    (setf *acceptor* (make-instance 'easy-acceptor :port port))
    (setf (dispatch-table *acceptor*)
          (list (create-prefix-dispatcher "/pipeline/run" #'pipeline-run-dispatch)
                (create-prefix-dispatcher "/pipeline/status" #'pipeline-status)
                (create-prefix-dispatcher "/pipeline" #'pipeline-page)
                (create-prefix-dispatcher "/manifest" #'manifest-page)
                (create-prefix-dispatcher "/scan" #'scan-dispatch)
                (create-prefix-dispatcher "/photo/" #'photo-dispatch)
                (create-prefix-dispatcher "/upload" #'upload-dispatch)
                (create-prefix-dispatcher "/" #'index-page)))
    (start *acceptor*))
  *acceptor*)

(defun stop ()
  (when *acceptor*
    (stop *acceptor*)
    (setf *acceptor* nil)))
