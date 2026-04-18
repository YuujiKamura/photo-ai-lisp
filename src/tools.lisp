(in-package #:photo-ai-lisp)

;;; Tool registry used by the resident agent.
;;; Each tool is a plist: (:name STRING :description STRING :function SYMBOL :schema ALIST)
;;; The agent receives (tools-schema-json), then emits tool-call JSON that
;;; (dispatch-tool) parses and runs.

(defun tool-scan-photos (args)
  (let ((dir (gethash "dir" args)))
    (unless (stringp dir) (error "scan_photos: missing \"dir\""))
    (run-skill "photo-scan" dir)))

(defun tool-run-pipeline (args)
  (let ((dir (gethash "dir" args)))
    (unless (stringp dir) (error "run_pipeline: missing \"dir\""))
    (run-pipeline dir)
    (list :ok t :pipeline-started t :dir dir)))

(defun tool-list-photos (args)
  (declare (ignore args))
  (mapcar (lambda (p)
            (list :id       (photo-id p)
                  :path     (photo-path p)
                  :category (string-downcase (symbol-name (photo-category p)))
                  :uploaded (photo-uploaded-at p)))
          (all-photos)))

(defun tool-export-pdf (args)
  (let ((matched (gethash "matched_json_path" args))
        (out-dir (gethash "out_dir"           args))
        (bin     (namestring *rust-export-binary*)))
    (unless (stringp matched) (error "export_pdf: missing \"matched_json_path\""))
    (unless (stringp out-dir) (error "export_pdf: missing \"out_dir\""))
    (unless (probe-file *rust-export-binary*)
      (error "export_pdf: rust binary not found at ~A" bin))
    (multiple-value-bind (so se code)
        (uiop:run-program (list bin "export" "--input" matched "--output-dir" out-dir)
                          :output :string :error-output :string :ignore-error-status t)
      (list :ok (zerop code) :stdout so :stderr se :exit-code code))))

(defun tool-eval-lisp (args)
  (let ((form-str (gethash "form_string" args)))
    (unless (stringp form-str) (error "eval_lisp: missing \"form_string\""))
    (parse-and-eval-expr form-str)))

(defparameter *tools*
  `((:name "scan_photos"
     :description "Scan a directory for JPEG photos and return the EXIF manifest."
     :function tool-scan-photos
     :schema (("dir" . "Absolute path to a directory of JPEG photos.")))
    (:name "run_pipeline"
     :description "Kick off the full photo-ai pipeline (scan, scope-infer, match, export) in a background thread."
     :function tool-run-pipeline
     :schema (("dir" . "Absolute path to a directory of JPEG photos.")))
    (:name "list_photos"
     :description "Return every in-memory photo as a list of plists."
     :function tool-list-photos
     :schema ())
    (:name "export_pdf"
     :description "Run the Rust exporter (*rust-export-binary*) to produce the PDF / Excel deliverables for a matched.json."
     :function tool-export-pdf
     :schema (("matched_json_path" . "Path to matched.json produced by the match step.")
              ("out_dir"           . "Directory where the PDF / Excel output should be written.")))
    (:name "eval_lisp"
     :description "Evaluate an arbitrary Lisp form inside the photo-ai-lisp package. Localhost-only."
     :function tool-eval-lisp
     :schema (("form_string" . "A Common Lisp form, as a string.")))))

(defun tool-by-name (name)
  (find name *tools* :key (lambda (tool) (getf tool :name)) :test #'string=))

(defun tools-schema-json ()
  "JSON description of every registered tool, suitable for agent handshake."
  (with-output-to-string (s)
    (yason:encode
     (mapcar (lambda (tool)
               (let ((h (make-hash-table :test 'equal))
                     (params (make-hash-table :test 'equal)))
                 (setf (gethash "name"        h) (getf tool :name)
                       (gethash "description" h) (getf tool :description))
                 (dolist (p (getf tool :schema))
                   (setf (gethash (car p) params) (cdr p)))
                 (setf (gethash "params" h) params)
                 h))
             *tools*)
     s)))

(defun dispatch-tool (tool-call-json-string)
  "Parse a tool-call JSON of the form
   {\"tool\":\"<name>\",\"args\":{...}}
and return a JSON result string:
   {\"ok\":true,\"result\":...} on success
   {\"ok\":false,\"error\":...} on failure."
  (let ((out (make-string-output-stream)))
    (handler-case
        (let* ((call (yason:parse tool-call-json-string))
               (name (and (hash-table-p call) (gethash "tool" call)))
               (args (or (and (hash-table-p call) (gethash "args" call))
                         (make-hash-table :test 'equal)))
               (tool (and name (tool-by-name name))))
          (cond
            ((null name)
             (write-string "{\"ok\":false,\"error\":" out)
             (yason:encode "missing \"tool\" field" out)
             (write-string "}" out))
            ((null tool)
             (write-string "{\"ok\":false,\"error\":" out)
             (yason:encode (format nil "unknown tool: ~A" name) out)
             (write-string "}" out))
            (t
             (handler-case
                 (let ((result (funcall (getf tool :function) args)))
                   (write-string "{\"ok\":true,\"result\":" out)
                   (yason:encode (prin1-to-string result) out)
                   (write-string "}" out))
               (error (c)
                 (write-string "{\"ok\":false,\"error\":" out)
                 (yason:encode (princ-to-string c) out)
                 (write-string "}" out))))))
      (error (c)
        (let ((buf (make-string-output-stream)))
          (write-string "{\"ok\":false,\"error\":" buf)
          (yason:encode (format nil "tool-call parse failed: ~A" c) buf)
          (write-string "}" buf)
          (return-from dispatch-tool (get-output-stream-string buf)))))
    (get-output-stream-string out)))
