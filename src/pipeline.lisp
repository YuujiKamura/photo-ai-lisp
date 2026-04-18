(in-package #:photo-ai-lisp)

(defvar *rust-export-binary*
  (merge-pathnames (if (uiop:os-windows-p)
                       "exporters/target/release/photo-ai-rust.exe"
                       "exporters/target/release/photo-ai-rust")
                   (user-homedir-pathname)))

(defvar *pipeline-state* nil)

(defun pipeline-make-steps ()
  (setf *pipeline-state*
        (list (list :name "scan"        :status :pending :artifact nil :error nil)
              (list :name "scope-infer" :status :pending :artifact nil :error nil)
              (list :name "match"       :status :pending :artifact nil :error nil)
              (list :name "export"      :status :pending :artifact nil :error nil))))

(defun pipeline-step (name)
  (find name *pipeline-state*
        :key (lambda (s) (getf s :name)) :test #'string=))

(defun set-step (name &key status artifact error)
  (let ((s (pipeline-step name)))
    (when s
      (when status   (setf (getf s :status)   status))
      (when artifact (setf (getf s :artifact) artifact))
      (when error    (setf (getf s :error)    error)))))

(defun run-pipeline (dir-string)
  (pipeline-make-steps)
  (bordeaux-threads:make-thread
   (lambda ()
     (block pipeline
       (let* ((dir (pathname dir-string))
              (out (merge-pathnames "photo-ai-output/" dir)))
         (ensure-directories-exist out)

         ;; Step 1: scan
         (set-step "scan" :status :running)
         (handler-case
             (let* ((manifest (run-skill "photo-scan" dir-string))
                    (mf (merge-pathnames "manifest.json" out)))
               (uiop:with-output-file (f mf :if-exists :supersede)
                 (yason:encode manifest f))
               (set-step "scan" :status :done :artifact (namestring mf)))
           (error (e)
             (set-step "scan" :status :failed :error (princ-to-string e))
             (return-from pipeline)))

         ;; Step 2: scope-infer (contact sheet only; AI analysis not automated here)
         (set-step "scope-infer" :status :running)
         (handler-case
             (let* ((mf     (merge-pathnames "manifest.json" out))
                    (cj     (merge-pathnames "contact.jpg" out))
                    (sf     (merge-pathnames "scope.json" out))
                    (script (namestring (skill-script-path "photo-scope-infer"))))
               (uiop:run-program (list (if (uiop:os-windows-p) "python" "python3") script (namestring mf)
                                       "--out" (namestring cj))
                                 :ignore-error-status t)
               (uiop:with-output-file (f sf :if-exists :supersede)
                 (write-string "{\"skipped\":true}" f))
               (set-step "scope-infer" :status :done :artifact (namestring cj)))
           (error (e)
             (set-step "scope-infer" :status :failed :error (princ-to-string e))))

         ;; Step 3: match (match.py needs photos.json + master.csv; master CSV path via --scope workaround)
         (set-step "match" :status :running)
         (handler-case
             (let* ((mf     (merge-pathnames "manifest.json" out))
                    (sf     (merge-pathnames "scope.json" out))
                    (xf     (merge-pathnames "matched.json" out))
                    (script (namestring (skill-script-path "photo-match-master"))))
               (multiple-value-bind (so se code)
                   (uiop:run-program (list (if (uiop:os-windows-p) "python" "python3") script (namestring mf)
                                           "--scope" (namestring sf)
                                           "--out" (namestring xf))
                                     :output :string :error-output :string :ignore-error-status t)
                 (declare (ignore so))
                 (if (zerop code)
                     (set-step "match" :status :done :artifact (namestring xf))
                     (set-step "match" :status :failed :error se))))
           (error (e)
             (set-step "match" :status :failed :error (princ-to-string e))))

         ;; Step 4: Rust export
         (set-step "export" :status :running)
         (handler-case
             (let* ((xf  (merge-pathnames "matched.json" out))
                    (bin (namestring *rust-export-binary*)))
               (if (probe-file *rust-export-binary*)
                   (multiple-value-bind (so se code)
                       (uiop:run-program (list bin "export"
                                               "--input" (namestring xf)
                                               "--output-dir" (namestring out))
                                         :output :string :error-output :string :ignore-error-status t)
                     (declare (ignore so))
                     (if (zerop code)
                         (set-step "export" :status :done :artifact (namestring out))
                         (set-step "export" :status :failed :error se)))
                   (set-step "export" :status :failed :error (format nil "Binary not found: ~A" bin))))
           (error (e)
             (set-step "export" :status :failed :error (princ-to-string e)))))))
   :name "pipeline"))
