(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(defun %claude-command ()
  "Return the claude command to use, accounting for Windows npm install.
   On Windows, the npm-shim .cmd wrapper does not propagate stdin through
   uiop:launch-program :input :stream reliably (stdin is closed before
   the wrapped node.exe reads it), so we only return a command when
   plain `claude' is directly invocable."
  (handler-case
      (progn (uiop:run-program '("claude" "--version")
                               :output nil :error-output nil)
             "claude")
    (error () nil)))

(defun claude-available-p ()
  (not (null (%claude-command))))

(test agent-sends-prompt-and-gets-response
  "Spawn real claude -p, send a trivial prompt, assert non-empty response.
   Skips when claude is not installed."
  (if (not (claude-available-p))
      (skip "claude not on PATH — skipping agent scenario test")
      (let ((photo-ai-lisp::*agent-process* nil)
            (cmd (%claude-command)))
        (unwind-protect
             (progn
               (photo-ai-lisp::start-agent :command cmd
                                           :args '("-p" "--model" "haiku"))
               (is-true (photo-ai-lisp::agent-alive-p)
                        "agent process should be alive after start-agent")
               (let ((reply (photo-ai-lisp::agent-send
                             "Reply with exactly one word: pong"
                             :timeout-seconds 30)))
                 (is (and (stringp reply) (> (length reply) 0))
                     "agent-send should return a non-empty string (got: ~S)" reply)))
          (ignore-errors (photo-ai-lisp::stop-agent))))))
