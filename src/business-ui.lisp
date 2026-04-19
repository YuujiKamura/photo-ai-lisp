(in-package #:photo-ai-lisp)

;;; Policy directive #04 — minimum viable business UI.
;;;
;;; STUBS only. Every function body signals UNIMPLEMENTED so
;;; tests/business-ui-tests.lisp can load without redefining
;;; symbols. Atoms under .dispatch/codex-business-ui-NN-*.md fill
;;; in behaviour.
;;;
;;; This file DOES NOT replace the terminal (/shell owned by
;;; src/term.lisp). Business UI embeds /shell?case=<path> via
;;; iframe in the case view; it never re-implements the byte pipe.

;; ---- config --------------------------------------------------------------

(defvar *case-root*
  (uiop:ensure-directory-pathname
   (merge-pathnames "photo-ai-cases/"
                    (uiop:getenv-pathname "USERPROFILE" :want-directory t)))
  "Root directory scanned for cases. Each immediate subdirectory is
   treated as one case. Configurable; tests rebind to a temp dir.")

;; ---- case scan + id ------------------------------------------------------

(defun scan-cases (&optional (root *case-root*))
  "Return a list of PHOTO-CASE objects — one per immediate
   subdirectory of ROOT. Does not recurse. Returns NIL on missing
   or empty root."
  (when (uiop:directory-exists-p root)
    (loop for subdir in (uiop:subdirectories root)
          for case = (case-from-directory subdir)
          when case collect case)))

(defun %url-safe-char-p (ch)
  (or (alphanumericp ch)
      (member ch '(#\- #\_))))

(defun %slugify (s)
  (let ((out (make-string (length s))))
    (dotimes (i (length s) out)
      (let ((ch (char s i)))
        (setf (char out i)
              (if (%url-safe-char-p ch)
                  (char-downcase ch)
                  #\-))))))

(defun case-id (case)
  "Stable URL-safe identifier for CASE. Deterministic: same
   CASE -> same id across calls. Derived from the directory
   basename; collisions resolved with a short hash suffix."
  (let* ((path     (photo-case-path case))
         (dir-list (pathname-directory path))
         (basename (if (consp dir-list)
                       (or (car (last dir-list)) "")
                       ""))
         (slug     (%slugify basename)))
    (if (zerop (length slug))
        (format nil "case-~8,'0x" (sxhash (namestring path)))
        slug)))

(defun case-from-id (id &optional (root *case-root*))
  "Return the PHOTO-CASE whose CASE-ID equals ID, scanning under
   ROOT. NIL if no match. Stable inverse of CASE-ID within a
   given ROOT contents snapshot."
  (find id (scan-cases root)
        :key  #'case-id
        :test #'equal))

;; ---- HTTP handlers -------------------------------------------------------

(defun list-cases-handler ()
  "HTTP handler body for GET /cases. Returns a JSON string:
     [{\"id\":...,\"name\":...,\"path\":...,\"has_reference\":bool}, ...]
   Empty array when no cases."
  (%unimpl 'list-cases-handler))

(defun case-view-handler (id)
  "HTTP handler body for GET /cases/:id. Returns an HTML string
   with a left meta pane and a right <iframe> embedding
   /shell?case=<url-encoded-path>. For unknown ID, returns an
   error HTML body (status set by the easy-handler wrapper)."
  (declare (ignore id))
  (%unimpl 'case-view-handler))

(defun home-handler ()
  "HTTP handler body for GET /. Renders the case list page
   (delegates to LIST-CASES-HANDLER for data, then HTML-wraps it),
   or emits an HTTP redirect to /cases — implementer's choice."
  (format nil "<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\">
  <title>photo-ai-lisp</title>
  <meta http-equiv=\"refresh\" content=\"0; url=/cases\">
</head>
<body>
  <p>Redirecting to <a href=\"/cases\">/cases</a>...</p>
</body>
</html>"))
