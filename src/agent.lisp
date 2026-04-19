(in-package #:photo-ai-lisp)

(defvar *agent-command* "claude"
  "Path or basename of the agent CLI. Must be on PATH.")

(defvar *agent-args* '("-p" "--model" "haiku")
  "Arguments passed to *agent-command* on spawn.
   The -p flag causes claude to read one prompt from stdin and exit.")

(defvar *agent-process* nil
  "DEPRECATED: Lisp no longer manages agent processes directly.")

(defun agent-alive-p ()
  "Return true while the agent is available via CP (placeholder)."
  t)

(defun start-agent (&key (command nil command-supplied-p) (args nil args-supplied-p))
  "DEPRECATED: Use Control Plane to manage agent lifecycle."
  (declare (ignore command command-supplied-p args args-supplied-p))
  (warn "start-agent is deprecated. Use CP instead.")
  nil)

(defun stop-agent ()
  "DEPRECATED: Use Control Plane to manage agent lifecycle."
  (warn "stop-agent is deprecated. Use CP instead.")
  t)

(defun agent-send (msg &key (timeout-seconds 30))
  "DEPRECATED: Use photo-ai-lisp:invoke-via-cp instead.
   This remains as a temporary shim for legacy code."
  (declare (ignore msg timeout-seconds))
  (warn "agent-send is deprecated. Use CP instead.")
  "")
