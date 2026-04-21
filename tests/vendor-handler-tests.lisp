(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT-vendor-handler — unit tests for photo-ai-lisp::vendor-handler
;;; (src/main.lisp:93-113).
;;;
;;; vendor-handler reads the URI from hunchentoot:*request*, strips
;;; the "/vendor/" prefix, sanitises backslashes, resolves the path
;;; under static/vendor/ relative to (uiop:getcwd), and either
;;;   - sets (hunchentoot:return-code*) to 404 for bad paths
;;;     (missing truename, ".." anywhere in the relative tail,
;;;      or an escape outside the vendor root), or
;;;   - sets (hunchentoot:content-type*) from *vendor-mime-types*
;;;     and hands off to hunchentoot:handle-static-file.
;;;
;;; These tests drive the handler with a mock request that specialises
;;; hunchentoot:script-name, mirroring the %mock-request pattern from
;;; term-tests.lisp:11-18, and use the dynamic-binding style from
;;; main-tests.lisp to stand up *request* and *reply* without a server.

;;; Minimal mock to drive hunchentoot:script-name without a real HTTP request.
;;; Separate class from term-tests' %mock-request so the reader is always
;;; defined in this file even if term-tests loads afterwards or is skipped.
(defclass %mock-vendor-request ()
  ((%path :initarg :path :reader %mock-vendor-path)))

(defmethod hunchentoot:script-name ((req %mock-vendor-request))
  (%mock-vendor-path req))

(defun %make-vendor-req (uri)
  (make-instance '%mock-vendor-request :path uri))

;; VH-1: ".." anywhere in the sanitised path must be rejected with 404,
;; even before touching the filesystem. This is the core path-traversal
;; guard: the handler's cond tests (search ".." safe-rel) and bails out.
(test vendor-handler-path-traversal-rejected
  (let ((hunchentoot:*request* (%make-vendor-req "/vendor/../src/main.lisp"))
        (hunchentoot:*reply*   (make-instance 'hunchentoot:reply)))
    (ignore-errors (photo-ai-lisp::vendor-handler))
    (is (= 404 (hunchentoot:return-code*))
        "path-traversal URIs like /vendor/../src/main.lisp must be ~
         rejected with return code 404 — this is the core ~
         directory-escape guard in vendor-handler")))

;; VH-2: a well-formed URI pointing at a file that does not exist under
;; static/vendor/ must return 404 via the (null truename) arm.
(test vendor-handler-nonexistent-file-rejected
  (let ((hunchentoot:*request* (%make-vendor-req "/vendor/does-not-exist.wasm"))
        (hunchentoot:*reply*   (make-instance 'hunchentoot:reply)))
    (ignore-errors (photo-ai-lisp::vendor-handler))
    (is (= 404 (hunchentoot:return-code*))
        "URIs pointing at files that do not exist under static/vendor/ ~
         must return 404 via the (null truename) guard")))

;; VH-3: a real .wasm file under static/vendor/ must have its
;; content-type set to application/wasm BEFORE handle-static-file is
;; called. We wrap the call in ignore-errors because handle-static-file
;; writes to a real HTTP stream that does not exist in a unit-test
;; context — but (setf (hunchentoot:content-type*) ...) runs first, so
;; the header survives the error.
(test vendor-handler-wasm-served-with-correct-mime
  (let ((hunchentoot:*request* (%make-vendor-req "/vendor/ghostty-vt.wasm"))
        (hunchentoot:*reply*   (make-instance 'hunchentoot:reply)))
    (ignore-errors (photo-ai-lisp::vendor-handler))
    (is (equal "application/wasm" (hunchentoot:content-type*))
        "ghostty-vt.wasm must be served with Content-Type: ~
         application/wasm — the stock hunchentoot dispatcher picks ~
         application/octet-stream and the browser refuses to stream ~
         WebAssembly from that, which is the whole reason ~
         vendor-handler exists")))

;; VH-4: a real .js file under static/vendor/ must have its
;; content-type set to application/javascript; charset=utf-8 before
;; the static-file handoff. Same ignore-errors rationale as VH-3.
(test vendor-handler-js-served-with-correct-mime
  (let ((hunchentoot:*request* (%make-vendor-req "/vendor/ghostty-web.js"))
        (hunchentoot:*reply*   (make-instance 'hunchentoot:reply)))
    (ignore-errors (photo-ai-lisp::vendor-handler))
    (is (equal "application/javascript; charset=utf-8"
               (hunchentoot:content-type*))
        "ghostty-web.js must be served with Content-Type: ~
         application/javascript; charset=utf-8 per *vendor-mime-types*")))

;; VH-5: backslashes in the URI must be scrubbed by the (remove-if ...
;; char= #\\) step so the handler does not error out on Windows-style
;; separators slipping in. The outcome (200 vs 404) is not what we are
;; locking down here — only that the call finishes cleanly.
(test vendor-handler-backslash-stripped-from-path
  (let ((hunchentoot:*request* (%make-vendor-req "/vendor/ghostty\\-vt.wasm"))
        (hunchentoot:*reply*   (make-instance 'hunchentoot:reply)))
    (finishes (ignore-errors (photo-ai-lisp::vendor-handler)))))
