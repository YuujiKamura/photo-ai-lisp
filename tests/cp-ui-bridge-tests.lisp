(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; Acceptance specs for src/cp-ui-bridge.lisp (issue #19 T2.b).
;;; Tests are pure Lisp — no HTTP server started.  The bridge handler
;;; function is called directly and the returned JSON body is inspected.

;;; T2.h helper: temporarily unset PHOTO_AI_LISP_DEMO_AGENT for legacy
;;; branch tests, in case CI (or a developer) has it set in the env.
;;; Using (setf (uiop:getenv ...) nil) relies on uiop's setenv shim,
;;; which maps to sb-posix:setenv on SBCL/POSIX and SetEnvironmentVariableA
;;; on SBCL/Windows. Both accept "" as the unset-equivalent.
(defmacro %with-demo-agent-unset (&body body)
  `(let ((saved (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")))
     (unwind-protect
          (progn
            (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") "")
            ,@body)
       (when saved
         (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") saved)))))

;; ---- T2.b-1 : 503 body when *demo-session-id* is nil ------------------

(5am:test cp-ui-bridge-nil-session-returns-error-body
  "With *demo-session-id* nil, input-bridge-handler must return the
   error JSON body (the HTTP 503 status is set by the dispatcher wrapper;
   here we verify only the string contract).

   T2.h pivot: also asserts the PHOTO_AI_LISP_DEMO_AGENT env var is
   NOT set, so the legacy CP branch is exercised (not the shell-broadcast
   branch)."
  (%with-demo-agent-unset
    (let ((photo-ai-lisp:*demo-session-id* nil))
      (let ((body (photo-ai-lisp:input-bridge-handler "fake" "echo hello")))
        (5am:is (search "error" body)
                "body should contain 'error' key")
        (5am:is (search "no demo session" body)
                "body should contain the 'no demo session' message")))))

;; ---- T2.b-2 : 200 body when *demo-session-id* is set ------------------

(5am:test cp-ui-bridge-with-session-returns-ok-body
  "With *demo-session-id* bound to a non-nil string and *demo-cp-client*
   left as nil (falls back to :mock-client inside %cp-client-or-mock),
   input-bridge-handler must return a JSON body containing 'ok':true and
   the session id.

   T2.h pivot: PHOTO_AI_LISP_DEMO_AGENT must be unset for this test to
   exercise the legacy CP branch (otherwise the demo-mode branch takes
   over and returns a different JSON shape)."
  (%with-demo-agent-unset
    (let ((photo-ai-lisp:*demo-session-id* "test-sess-001")
          (photo-ai-lisp:*demo-cp-client*  nil))
      (let ((body (photo-ai-lisp:input-bridge-handler "test-case" "echo hello from hub")))
        (5am:is (search "\"ok\":true" body)
                "body should contain ok:true")
        (5am:is (search "test-sess-001" body)
                "body should echo the session id")
        (5am:is (search "bytes" body)
                "body should contain byte count field")))))

;; ---- T2.h : demo-mode branch returns error body when no /ws/shell is open -----

(5am:test input-bridge-demo-mode-no-recipients-returns-error
  "With PHOTO_AI_LISP_DEMO_AGENT set but no /ws/shell client connected,
   shell-broadcast-input reaches zero recipients, so input-bridge-handler
   must return the 'no /ws/shell client connected' error body. The
   dispatcher wrapper in src/main.lisp will set HTTP 503 based on the
   'error' substring in the body."
  (let ((saved (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")))
    (unwind-protect
         (progn
           ;; No /ws/shell client is ever connected during unit tests
           ;; (acceptor isn't running), so shell-broadcast-input counts 0
           ;; recipients by construction. Setting the env var forces the
           ;; demo-mode branch without needing to mock anything.
           (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")
                 "claude --model sonnet")
           (let ((photo-ai-lisp:*demo-session-id* nil)
                 (photo-ai-lisp:*demo-cp-client*  nil))
             (let ((body (photo-ai-lisp:input-bridge-handler "demo" "echo hi")))
               (5am:is (search "\"error\"" body)
                       "body must contain JSON 'error' key so dispatcher 503s")
               (5am:is (search "no /ws/shell" body)
                       "body must name the missing /ws/shell client"))))
      (if saved
          (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") saved)
          (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") "")))))

;; ---- T2.c — parse-demo-session-name unit tests ----------------------------

(5am:test boot-hub-parse-demo-session-simple
  "Single line 'ghostty-12345\\n' -> 'ghostty-12345'."
  (5am:is (equal "ghostty-12345"
                 (photo-ai-lisp:parse-demo-session-name
                  (format nil "ghostty-12345~%")))
          "simple ghostty session name must be returned verbatim"))

(5am:test boot-hub-parse-demo-session-multiline
  "Noise lines before the session name: last non-empty line wins."
  (5am:is (equal "ghostty-67890"
                 (photo-ai-lisp:parse-demo-session-name
                  (format nil "some noise~%ghostty-67890~%")))
          "last non-empty line should be returned even when prefix noise is present"))

(5am:test boot-hub-parse-demo-session-bad-input
  "Empty string and non-ghostty- prefix → nil."
  (5am:is (null (photo-ai-lisp:parse-demo-session-name ""))
          "empty string must return nil")
  (5am:is (null (photo-ai-lisp:parse-demo-session-name
                 (format nil "notasession~%")))
          "line not starting with ghostty- must return nil"))
