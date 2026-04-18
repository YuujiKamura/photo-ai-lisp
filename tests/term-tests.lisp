(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT2 — unit tests for src/term.lisp
;;; Tests class hierarchy, resource instances, URL dispatch, dispatch table,
;;; and HTML page content.  No server is started; WebSocket protocol methods
;;; are not exercised (integration territory).

;;; Minimal mock to drive hunchentoot:script-name without a real HTTP request.
(defclass %mock-request ()
  ((%path :initarg :path)))

(defmethod hunchentoot:script-name ((req %mock-request))
  (slot-value req '%path))

(defun %make-req (path)
  (make-instance '%mock-request :path path))

;; UT2a: ws-easy-acceptor inherits from both WebSocket and easy-acceptor.
(test term-ws-easy-acceptor-inherits-websocket-acceptor
  (is-true (subtypep 'photo-ai-lisp::ws-easy-acceptor
                     'hunchensocket:websocket-acceptor)
           "ws-easy-acceptor must be a subtype of websocket-acceptor"))

(test term-ws-easy-acceptor-inherits-easy-acceptor
  (is-true (subtypep 'photo-ai-lisp::ws-easy-acceptor
                     'hunchentoot:easy-acceptor)
           "ws-easy-acceptor must be a subtype of easy-acceptor"))

;; UT2b: global resource instances have the expected types.
(test term-echo-resource-type
  (is-true (typep photo-ai-lisp::*echo-resource*
                  'photo-ai-lisp::echo-resource)
           "*echo-resource* should be an echo-resource instance"))

(test term-shell-resource-type
  (is-true (typep photo-ai-lisp::*shell-resource*
                  'photo-ai-lisp::shell-resource)
           "*shell-resource* should be a shell-resource instance"))

;; UT2c: %find-echo-resource dispatches on /ws/echo, returns nil elsewhere.
(test term-find-echo-resource-match
  (is (eq photo-ai-lisp::*echo-resource*
          (photo-ai-lisp::%find-echo-resource (%make-req "/ws/echo")))
      "%find-echo-resource should return *echo-resource* for /ws/echo"))

(test term-find-echo-resource-no-match
  (is (null (photo-ai-lisp::%find-echo-resource (%make-req "/ws/shell")))
      "%find-echo-resource should return nil for /ws/shell")
  (is (null (photo-ai-lisp::%find-echo-resource (%make-req "/")))
      "%find-echo-resource should return nil for /"))

;; UT2d: %find-shell-resource dispatches on /ws/shell, returns nil elsewhere.
(test term-find-shell-resource-match
  (is (eq photo-ai-lisp::*shell-resource*
          (photo-ai-lisp::%find-shell-resource (%make-req "/ws/shell")))
      "%find-shell-resource should return *shell-resource* for /ws/shell"))

(test term-find-shell-resource-no-match
  (is (null (photo-ai-lisp::%find-shell-resource (%make-req "/ws/echo")))
      "%find-shell-resource should return nil for /ws/echo")
  (is (null (photo-ai-lisp::%find-shell-resource (%make-req "/")))
      "%find-shell-resource should return nil for /"))

;; UT2e: *websocket-dispatch-table* contains both dispatch functions.
(test term-dispatch-table-has-echo-fn
  (is-true (find 'photo-ai-lisp::%find-echo-resource
                 hunchensocket:*websocket-dispatch-table*)
           "*websocket-dispatch-table* should contain %find-echo-resource"))

(test term-dispatch-table-has-shell-fn
  (is-true (find 'photo-ai-lisp::%find-shell-resource
                 hunchensocket:*websocket-dispatch-table*)
           "*websocket-dispatch-table* should contain %find-shell-resource"))

;; UT2f: term-page returns HTML containing "xterm.js".
;;  hunchentoot:*reply* must be bound to avoid an unbound-variable error from
;;  (setf (content-type*) ...) inside the handler.
(test term-page-contains-xterm-js
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (let ((html (photo-ai-lisp::term-page)))
      (is-true (stringp html)
               "term-page should return a string")
      (is-true (search "xterm.js" html)
               "term-page HTML should reference xterm.js"))))

;; UT2g: shell-page returns HTML containing "xterm.js".
(test shell-page-contains-xterm-js
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (let ((html (photo-ai-lisp::shell-page)))
      (is-true (stringp html)
               "shell-page should return a string")
      (is-true (search "xterm.js" html)
               "shell-page HTML should reference xterm.js"))))
