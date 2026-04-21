(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT — unit tests for photo-ai-lisp::%vendor-content-type (src/main.lisp)
;;; The function maps a pathname's type to a Content-Type string via the
;;; *vendor-mime-types* alist (case-insensitive lookup through string-equal),
;;; falling back to "application/octet-stream" for unknown / missing types.

;; .wasm must resolve to application/wasm — browsers reject other MIME types
;; when loading WebAssembly modules through WebAssembly.instantiateStreaming.
(test vendor-mime-wasm-resolves-to-application-wasm
  (is (string= "application/wasm"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "foo" :type "wasm")))
      ".wasm must be served as application/wasm for streaming instantiation"))

;; .js must resolve to application/javascript with UTF-8 charset.
(test vendor-mime-js-resolves-to-application-javascript
  (is (string= "application/javascript; charset=utf-8"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "bundle" :type "js")))
      ".js must be served as application/javascript; charset=utf-8"))

;; .css must resolve to text/css with UTF-8 charset.
(test vendor-mime-css-resolves-to-text-css
  (is (string= "text/css; charset=utf-8"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "styles" :type "css")))
      ".css must be served as text/css; charset=utf-8"))

;; .map (source map) must resolve to application/json with UTF-8 charset.
(test vendor-mime-map-resolves-to-application-json
  (is (string= "application/json; charset=utf-8"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "bundle.js" :type "map")))
      ".map (source map) must be served as application/json; charset=utf-8"))

;; Unknown extension falls through the alist to application/octet-stream.
(test vendor-mime-unknown-extension-falls-back-to-octet-stream
  (is (string= "application/octet-stream"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "foo" :type "xyz")))
      "unknown extensions must fall back to application/octet-stream"))

;; A pathname with no type (pathname-type returns NIL) exercises the
;; (or (pathname-type pathname) "") guard and must still hit the fallback.
(test vendor-mime-missing-extension-falls-back-to-octet-stream
  (is (string= "application/octet-stream"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "foo")))
      "pathname-type NIL must not error and must fall back to octet-stream"))

;; Case-insensitive lookup: .WASM (uppercase) must still resolve to
;; application/wasm because the alist is queried with string-equal.
(test vendor-mime-uppercase-wasm-is-case-insensitive
  (is (string= "application/wasm"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "foo" :type "WASM")))
      "uppercase .WASM must resolve via case-insensitive string-equal lookup"))

;; Case-insensitive lookup: mixed-case .Js must still resolve to
;; application/javascript; charset=utf-8.
(test vendor-mime-mixedcase-js-is-case-insensitive
  (is (string= "application/javascript; charset=utf-8"
               (photo-ai-lisp::%vendor-content-type
                (make-pathname :name "bundle" :type "Js")))
      "mixed-case .Js must resolve via case-insensitive string-equal lookup"))
