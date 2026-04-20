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
   (merge-pathnames "demo/cases/" (uiop:getcwd)))
  "Root directory scanned for cases. Each immediate subdirectory is
   treated as one case. Configurable; tests rebind to a temp dir.")

(defvar *ghostty-web-url* (or (uiop:getenv "GHOSTTY_WEB_URL") "/shell")
  "URL for the terminal iframe. Defaults to '/shell' — this server's own
   page, which renders via the ghostty-web WASM bundle vendored under
   static/vendor/ and connects back to /ws/shell (Lisp-owned PTY). Keeps
   the whole terminal story in one Lisp process: /api/inject, the agent
   picker auto-inject, and Swank hot-reload all reach the same PTY.
   Set GHOSTTY_WEB_URL to override with an external daemon if needed.")

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

;;; (using %json-escape from case.lisp)

(defun %case->json (c)
  (format nil "{\"id\":\"~a\",\"name\":\"~a\",\"path\":\"~a\",\"has_reference\":~a}"
          (%json-escape (case-id c))
          (%json-escape (or (photo-case-name c) ""))
          (%json-escape (namestring (photo-case-path c)))
          (if (photo-case-reference-path c) "true" "false")))

(defun list-cases-handler ()
  "HTTP handler body for GET /cases. Returns a JSON string:
     [{\"id\":...,\"name\":...,\"path\":...,\"has_reference\":bool}, ...]
   Empty array when no cases."
  (let ((objs (mapcar #'%case->json (scan-cases))))
    (format nil "[~{~a~^,~}]" objs)))

(defun %case-basename (case)
  (let* ((path (photo-case-path case))
         (dir-list (pathname-directory path)))
    (if (consp dir-list)
        (or (car (last dir-list)) "")
        "")))

(defun case-view-handler (id)
  "HTTP handler body for GET /cases/:id. Returns an HTML string
   with a left meta pane and a right <iframe> embedding
   /shell?case=<url-encoded-path>. For unknown ID, returns an
   error HTML body (status set by the easy-handler wrapper)."
  (let ((c (case-from-id id)))
    (if (null c)
        (format nil "<!DOCTYPE html>
<html><head><meta charset=\"utf-8\"><title>Case Not Found</title></head>
<body><h1>Error: unknown case id ~a</h1></body></html>"
                (%json-escape id))
        (let* ((path-ns (namestring (photo-case-path c)))
               (encoded (hunchentoot:url-encode path-ns))
               (name    (or (photo-case-name c)
                            (%case-basename c))))
          (format nil "<!DOCTYPE html>
<html>
<head><meta charset=\"utf-8\"><title>~a</title>
<style>
  body { margin:0; font-family:Menlo,Consolas,monospace; }
  .split { display:flex; height:100vh; }
  .meta  { width:35%; padding:12px; overflow:auto; border-right:1px solid #ccc; }
  .term  { flex:1; }
  iframe { width:100%; height:100%; border:0; }
  pre    { white-space:pre-wrap; }
</style></head>
<body>
  <div class=\"split\">
    <div class=\"meta\">
      <h1>~a</h1>
      <pre>path: ~a
reference: ~a
masters:   ~a</pre>
    </div>
    <div class=\"term\">
      <iframe src=\"~a/shell?case=~a\"></iframe>
    </div>
  </div>
</body></html>"
                  name name path-ns
                  (or (and (photo-case-reference-path c)
                           (namestring (photo-case-reference-path c)))
                      "(none)")
                  (or (and (photo-case-masters-dir c)
                           (namestring (photo-case-masters-dir c)))
                      "(none)")
                  *ghostty-web-url*
                  encoded)))))

(defvar *static-root*
  (uiop:ensure-directory-pathname
   (merge-pathnames "static/" (uiop:getcwd)))
  "Directory containing static HTML/CSS/JS assets.")

(defvar *masters-root*
  (uiop:ensure-directory-pathname
   (merge-pathnames "masters/" (uiop:getcwd)))
  "Directory containing master CSV files bundled with the distribution.")

;; ---- master CSV loader ---------------------------------------------------

(defun %split-csv-line (line)
  "Split LINE on commas. No quoting support — our master CSVs use plain
   ASCII delimiters and pipe-separated aliases."
  (loop with start = 0
        with len = (length line)
        for i from 0 to len
        when (or (= i len) (char= (char line i) #\,))
          collect (subseq line start i)
          and do (setf start (1+ i))))

(defun %split-aliases (s)
  "Split pipe-delimited alias cell into a list of non-empty strings."
  (when (and s (plusp (length s)))
    (loop with start = 0
          with len = (length s)
          for i from 0 to len
          when (or (= i len) (char= (char s i) #\|))
            collect (subseq s start i) into parts
            and do (setf start (1+ i))
          finally (return (remove-if (lambda (x) (zerop (length x))) parts)))))

(defun %strip-bom (s)
  "Strip a leading UTF-8 BOM (#\\Zero-Width-No-Break-Space) if present."
  (if (and (plusp (length s)) (char= (char s 0) (code-char #xFEFF)))
      (subseq s 1)
      s))

(defun %chomp (s)
  "Trim trailing CR/LF from S."
  (let ((end (length s)))
    (loop while (and (plusp end)
                     (let ((ch (char s (1- end))))
                       (or (char= ch #\Return) (char= ch #\Newline))))
          do (decf end))
    (subseq s 0 end)))

(defun read-master-csv (relpath)
  "Read a master CSV file under *MASTERS-ROOT* and return a list of
   plists: ((:id \"...\" :label-ja \"...\" :parent-id \"...\" :aliases (...)) ...).
   Expects header line `id,label_ja,parent_id,aliases`. Returns NIL if
   the file does not exist."
  (let ((path (merge-pathnames relpath *masters-root*)))
    (when (uiop:file-exists-p path)
      (with-open-file (in path :direction :input
                               :external-format :utf-8)
        (let ((header-line (read-line in nil nil)))
          (declare (ignore header-line))
          (loop for raw = (read-line in nil nil)
                while raw
                for line = (%chomp (%strip-bom raw))
                when (plusp (length line))
                  collect (let ((cols (%split-csv-line line)))
                            (list :id        (nth 0 cols)
                                  :label-ja  (nth 1 cols)
                                  :parent-id (or (nth 2 cols) "")
                                  :aliases   (%split-aliases (nth 3 cols))))))))))

(defun %master-file-stem (path)
  "Return the file name without extension for PATH, e.g.
   work-category.csv -> \"work-category\"."
  (or (pathname-name path) ""))

(defun %row->json (row)
  (format nil
          "{\"id\":\"~a\",\"label_ja\":\"~a\",\"parent_id\":\"~a\",\"aliases\":[~{\"~a\"~^,~}]}"
          (%json-escape (or (getf row :id) ""))
          (%json-escape (or (getf row :label-ja) ""))
          (%json-escape (or (getf row :parent-id) ""))
          (mapcar #'%json-escape (or (getf row :aliases) '()))))

(defun %master-file->json (path)
  (let* ((stem (%master-file-stem path))
         (rel  (concatenate 'string stem ".csv"))
         (rows (read-master-csv rel))
         (rows-json (mapcar #'%row->json rows)))
    (format nil "{\"file\":\"~a\",\"rows\":[~{~a~^,~}]}"
            (%json-escape stem)
            rows-json)))

(defun list-masters-handler ()
  "HTTP handler body for GET /api/masters. Returns a JSON array of
   {file, rows:[...]} objects, one per CSV file under *MASTERS-ROOT*.
   Returns an empty array if the directory does not exist."
  (if (uiop:directory-exists-p *masters-root*)
      (let* ((files (directory (merge-pathnames "*.csv" *masters-root*)))
             (sorted (sort (copy-list files) #'string<
                           :key (lambda (p) (or (pathname-name p) ""))))
             (objs (mapcar #'%master-file->json sorted)))
        (format nil "[~{~a~^,~}]" objs))
      "[]"))

(defun %read-static-file (relpath)
  "Read RELPATH under *static-root* as a string. NIL if missing."
  (let ((path (merge-pathnames relpath *static-root*)))
    (when (uiop:file-exists-p path)
      (uiop:read-file-string path))))

(defun home-handler ()
  "HTTP handler body for GET /. Serves static/index.html verbatim,
   injecting the ghostty-web URL as a data attribute on <html>.
   Falls back to a redirect stub when static/index.html is missing."
  (let ((html (%read-static-file "index.html")))
    (if html
        ;; Inject ghostty URL so JS can populate the iframe.
        (let ((injected (format nil "data-ghostty-url=\"~a\""
                                (%json-escape *ghostty-web-url*))))
          (cl-ppcre-free-replace html injected))
        (format nil "<!DOCTYPE html>
<html><head><meta charset=\"utf-8\"><title>photo-ai-lisp</title>
<meta http-equiv=\"refresh\" content=\"0; url=/cases\"></head>
<body><p>static/index.html not found. <a href=\"/cases\">/cases</a></p>
</body></html>"))))

(defun cl-ppcre-free-replace (html data-attr)
  "Insert DATA-ATTR into the <html ...> opening tag without depending
   on cl-ppcre. Case-sensitive literal match on '<html lang=\"ja\">'
   or plain '<html>'."
  (let ((lang-tag "<html lang=\"ja\">")
        (plain    "<html>"))
    (cond
      ((search lang-tag html)
       (let ((pos (search lang-tag html)))
         (concatenate 'string
                      (subseq html 0 pos)
                      (format nil "<html lang=\"ja\" ~a>" data-attr)
                      (subseq html (+ pos (length lang-tag))))))
      ((search plain html)
       (let ((pos (search plain html)))
         (concatenate 'string
                      (subseq html 0 pos)
                      (format nil "<html ~a>" data-attr)
                      (subseq html (+ pos (length plain))))))
      (t html))))
