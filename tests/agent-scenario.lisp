(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(defun %claude-command ()
  "Return the claude command to use, accounting for Windows npm install."
  (or (handler-case
          (progn (uiop:run-program '("claude" "--version")
                                   :output nil :error-output nil)
                 "claude")
        (error () nil))
      (when (uiop:os-windows-p)
        (let ((npm-claude (merge-pathnames
                           "AppData/Roaming/npm/claude.cmd"
                           (user-homedir-pathname))))
          (when (probe-file npm-claude)
            (namestring npm-claude))))))

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
