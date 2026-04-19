;;; Viaweb-style live-edit verification script
;;; Run: sbcl --non-interactive --load C:/Users/yuuji/viaweb-test.lisp

;; Step 1: Load app and start server
(ql:quickload :photo-ai-lisp :silent t)
(photo-ai-lisp:start)
(sleep 3)

;; Helper: first-occurrence string replace
(defun string-replace-first (haystack needle replacement)
  (let ((pos (search needle haystack)))
    (if pos
        (concatenate 'string
                     (subseq haystack 0 pos)
                     replacement
                     (subseq haystack (+ pos (length needle))))
        haystack)))

;; Step 2: Capture BEFORE response
(defvar *before*
  (uiop:run-program (list "curl" "-s" "http://localhost:8080/")
                    :output :string
                    :ignore-error-status t))

(format t "~%[BEFORE captured: ~A chars]~%" (length *before*))

;; Step 3: Patch main.lisp - insert live-edit line before (:table
(let* ((path "C:/Users/yuuji/photo-ai-lisp/src/main.lisp")
       (content (uiop:read-file-string path))
       (needle  "    (:table :border \"1\" :cellpadding \"6\"")
       (replacement (concatenate 'string
                                 "    (:p \"live-edit at 2026-04-18\")" (string #\Newline)
                                 "    (:table :border \"1\" :cellpadding \"6\"")))
  (if (search needle content)
      (progn
        (with-open-file (out path :direction :output :if-exists :supersede
                             :external-format :utf-8)
          (write-string (string-replace-first content needle replacement) out))
        (format t "[main.lisp patched]~%"))
      (format t "[WARNING: needle not found in main.lisp]~%")))

;; Step 4: Reload without restarting SBCL or Hunchentoot
(load "C:/Users/yuuji/photo-ai-lisp/src/main.lisp")
(format t "[main.lisp reloaded]~%")
(sleep 1)

;; Step 5: Capture AFTER response
(defvar *after*
  (uiop:run-program (list "curl" "-s" "http://localhost:8080/")
                    :output :string
                    :ignore-error-status t))

(format t "[AFTER captured: ~A chars]~%" (length *after*))

;; Write report file
(with-open-file (out "C:/Users/yuuji/viaweb-report.txt"
                     :direction :output
                     :if-exists :supersede
                     :external-format :utf-8)
  (format out "=== BEFORE (first 600 chars) ===~%~A~%~%=== AFTER (first 600 chars) ===~%~A~%~%=== MATCH? ===~%~A~%"
          (subseq *before* 0 (min 600 (length *before*)))
          (subseq *after*  0 (min 600 (length *after*)))
          (if (equal *before* *after*) "SAME - loop FAILED" "DIFFERENT - loop PASSED")))

(format t "[Report written to C:/Users/yuuji/viaweb-report.txt]~%")

;; Stop server
(photo-ai-lisp:stop)
(format t "[Server stopped]~%")

(uiop:quit 0)
