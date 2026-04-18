(in-package #:photo-ai-lisp)

;;; Policy directive #01 — minimum viable case CLOS model.
;;;
;;; This file currently contains STUBS only. Every symbol is defined
;;; so `tests/case-tests.lisp` can load, but the behaviour signals
;;; UNIMPLEMENTED until the atoms under `.dispatch/codex-NN-*.md`
;;; land. The test suite is intentionally red on this branch until
;;; the implementation lands.

(define-condition unimplemented (error)
  ((sym :initarg :sym :reader unimplemented-sym))
  (:report (lambda (c s)
             (format s "~a is a policy-01 stub — not yet implemented"
                     (unimplemented-sym c)))))

(defun %unimpl (sym)
  (error 'unimplemented :sym sym))

;; ---- case object model --------------------------------------------------

(defclass photo-case ()
  ((path           :initarg :path           :reader photo-case-path
                   :initform nil
                   :documentation "Absolute pathname to the case root directory.")
   (name           :initarg :name           :reader photo-case-name
                   :initform nil
                   :documentation "Human-readable identifier for this case.")
   (masters-dir    :initarg :masters-dir    :reader photo-case-masters-dir
                   :initform nil
                   :documentation "Directory holding master CSVs, or nil.")
   (reference-path :initarg :reference-path :reader photo-case-reference-path
                   :initform nil
                   :documentation "Path to case.xlsx (or equivalent), or nil.")))

(defun make-photo-case (&key path name masters-dir reference-path)
  "Direct constructor. No filesystem inspection."
  (make-instance 'photo-case
                 :path path
                 :name name
                 :masters-dir masters-dir
                 :reference-path reference-path))

(defun case-from-directory (directory)
  "Build a PHOTO-CASE by inspecting DIRECTORY. Populates REFERENCE-PATH
   when a case.xlsx exists at the top level; otherwise slots are nil."
  (let* ((dir (uiop:ensure-directory-pathname directory))
         (reference-path (merge-pathnames "case.xlsx" dir))
         (masters-dir (merge-pathnames "masters/" dir)))
    (make-photo-case
     :path dir
     :reference-path (when (uiop:file-exists-p reference-path)
                       reference-path)
     :masters-dir (when (uiop:directory-exists-p masters-dir)
                    masters-dir))))

(defvar *case-cache* (make-hash-table :test #'equal)
  "Canonical namestring -> PHOTO-CASE.")

(defvar *case-cache-lock* (bordeaux-threads:make-lock "case-cache")
  "Protects *CASE-CACHE* mutations.")

(defun find-case (path)
  "Return a PHOTO-CASE for PATH, creating (and caching) via
   CASE-FROM-DIRECTORY on first sight."
  (let* ((dir (uiop:ensure-directory-pathname path))
         (key (namestring (truename dir))))
    (bordeaux-threads:with-lock-held (*case-cache-lock*)
      (or (gethash key *case-cache*)
          (setf (gethash key *case-cache*)
                (case-from-directory dir))))))

;; ---- session registry ----------------------------------------------------

(defvar *sessions* (make-hash-table :test #'equal)
  "Session-id (string) -> PHOTO-CASE. One session = one browser tab.")

(defun register-session (session-id case)
  "Record SESSION-ID -> CASE. Overwrites any previous binding."
  (setf (gethash session-id *sessions*) case))

(defun lookup-session (session-id)
  "Return the PHOTO-CASE for SESSION-ID, or NIL."
  (gethash session-id *sessions*))

(defun clear-session (session-id)
  "Remove the binding for SESSION-ID. Idempotent."
  (remhash session-id *sessions*))

;; ---- env composition for subprocess --------------------------------------

(defun build-case-env (case)
  "Return an alist of (NAME . VALUE) env entries exposing CASE fields
   to a child process. Keys: PHOTO_AI_CASE_PATH, PHOTO_AI_CASE_NAME,
   PHOTO_AI_MASTERS_DIR. Nil slot values become empty strings."
  (flet ((slot->string (value)
           (cond ((null value) "")
                 ((pathnamep value) (namestring value))
                 (t (princ-to-string value)))))
    (list (cons "PHOTO_AI_CASE_PATH"
                (slot->string (photo-case-path case)))
          (cons "PHOTO_AI_CASE_NAME"
                (slot->string (photo-case-name case)))
          (cons "PHOTO_AI_MASTERS_DIR"
                (slot->string (photo-case-masters-dir case))))))

;; ---- request plumbing ----------------------------------------------------

(defun parse-shell-case-query (query-string)
  "Pull the `case=<urlencoded-path>` parameter out of a URL query
   string. Return the decoded path as a string, or NIL if absent."
  (when (and query-string (plusp (length query-string)))
    (loop for segment in (uiop:split-string query-string :separator "&")
          for eq-pos = (position #\= segment)
          when (and eq-pos (string= "case" (subseq segment 0 eq-pos)))
            do (let ((raw (subseq segment (1+ eq-pos))))
                 ;; Empty case= is treated as NIL for downstream /shell wiring.
                 (return (if (zerop (length raw))
                             nil
                             (hunchentoot:url-decode raw)))))))

(defun %json-escape (string)
  (with-output-to-string (out)
    (loop for ch across string do
      (cond ((char= ch #\\) (write-string "\\\\" out))
            ((char= ch #\") (write-string "\\\"" out))
            ((char= ch #\Backspace) (write-string "\\b" out))
            ((char= ch #\Page) (write-string "\\f" out))
            ((char= ch #\Newline) (write-string "\\n" out))
            ((char= ch #\Return) (write-string "\\r" out))
            ((char= ch #\Tab) (write-string "\\t" out))
            ((<= (char-code ch) 31) (format out "\\u~4,'0X" (char-code ch)))
            (t (write-char ch out))))))

(defun %slot-string (value)
  (cond ((null value) "")
        ((pathnamep value) (namestring value))
        (t (princ-to-string value))))

(defun %json-value (value)
  (%json-escape (%slot-string value)))

(defun api-session-handler (session-id)
  "HTTP handler body for GET /api/session/:id. Returns a JSON string
   with keys case_path, case_name, masters_dir, reference_path, or a
   JSON `{\"error\":\"not-found\"}` body when unknown."
  (let ((photo-case (lookup-session session-id)))
    (if photo-case
        (format nil
                "{\"id\":\"~a\",\"case_path\":\"~a\",\"case_name\":\"~a\",\"masters_dir\":\"~a\",\"reference_path\":\"~a\"}"
                (%json-value session-id)
                (%json-value (photo-case-path photo-case))
                (%json-value (photo-case-name photo-case))
                (%json-value (photo-case-masters-dir photo-case))
                (%json-value (photo-case-reference-path photo-case)))
        (format nil
                "{\"error\":\"not-found\",\"id\":\"~a\"}"
                (%json-value session-id)))))
