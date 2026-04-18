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

(defun find-case (path)
  "Return a PHOTO-CASE for PATH, creating (and caching) via
   CASE-FROM-DIRECTORY on first sight."
  (declare (ignore path))
  (%unimpl 'find-case))

;; ---- session registry ----------------------------------------------------

(defvar *sessions* (make-hash-table :test #'equal)
  "Session-id (string) -> PHOTO-CASE. One session = one browser tab.")

(defun register-session (session-id case)
  "Record SESSION-ID -> CASE. Overwrites any previous binding."
  (declare (ignore session-id case))
  (%unimpl 'register-session))

(defun lookup-session (session-id)
  "Return the PHOTO-CASE for SESSION-ID, or NIL."
  (declare (ignore session-id))
  (%unimpl 'lookup-session))

(defun clear-session (session-id)
  "Remove the binding for SESSION-ID. Idempotent."
  (declare (ignore session-id))
  (%unimpl 'clear-session))

;; ---- env composition for subprocess --------------------------------------

(defun build-case-env (case)
  "Return an alist of (NAME . VALUE) env entries exposing CASE fields
   to a child process. Keys: PHOTO_AI_CASE_PATH, PHOTO_AI_CASE_NAME,
   PHOTO_AI_MASTERS_DIR. Nil slot values become empty strings."
  (declare (ignore case))
  (%unimpl 'build-case-env))

;; ---- request plumbing ----------------------------------------------------

(defun parse-shell-case-query (query-string)
  "Pull the `case=<urlencoded-path>` parameter out of a URL query
   string. Return the decoded path as a string, or NIL if absent."
  (declare (ignore query-string))
  (%unimpl 'parse-shell-case-query))

(defun api-session-handler (session-id)
  "HTTP handler body for GET /api/session/:id. Returns a JSON string
   with keys case_path, case_name, masters_dir, reference_path, or a
   JSON `{\"error\":\"not-found\"}` body when unknown."
  (declare (ignore session-id))
  (%unimpl 'api-session-handler))
