(in-package #:photo-ai-lisp)

(defvar *agent-command* "claude"
  "Path or basename of the agent CLI. Must be on PATH.")

(defvar *agent-args* '("-p" "--model" "haiku")
  "Arguments passed to *agent-command* on spawn.
   The -p flag causes claude to read one prompt from stdin and exit.")

(defvar *agent-process* nil
  "uiop process-info for the currently running agent, or NIL.")

(defun agent-alive-p ()
  "Return true while the agent subprocess is still running."
  (and *agent-process* (uiop:process-alive-p *agent-process*)))

(defun agent-stdin  () (and *agent-process* (uiop:process-info-input  *agent-process*)))
(defun agent-stdout () (and *agent-process* (uiop:process-info-output *agent-process*)))

(defun start-agent (&key (command nil command-supplied-p) (args nil args-supplied-p))
  "Spawn the agent subprocess."
  (when command-supplied-p (setf *agent-command* command))
  (when args-supplied-p    (setf *agent-args*    args))
  (when (agent-alive-p)
    (return-from start-agent *agent-process*))
  (setf *agent-process*
        (uiop:launch-program (cons *agent-command* *agent-args*)
                             :input :stream
                             :output :stream
                             :error-output :stream))
  *agent-process*)

(defun stop-agent ()
  "Terminate the agent subprocess if it is running."
  (when *agent-process*
    (ignore-errors (close (agent-stdin)))
    (ignore-errors (uiop:terminate-process *agent-process*))
    (ignore-errors (uiop:wait-process *agent-process*))
    (setf *agent-process* nil))
  t)

(defun agent-send (msg &key (timeout-seconds 30))
  "Write MSG to the agent's stdin, close stdin so the process sees EOF,
then read all stdout until the process exits or TIMEOUT-SECONDS elapses.
Returns the response as a string, or empty string when no agent is live."
  (unless (agent-alive-p)
    (return-from agent-send ""))
  (let ((in  (agent-stdin))
        (out (agent-stdout)))
    (write-line msg in)
    (finish-output in)
    (ignore-errors (close in))
    (let ((deadline (+ (get-internal-real-time)
                       (* timeout-seconds internal-time-units-per-second)))
          (buf (make-string-output-stream)))
      (loop
        (when (> (get-internal-real-time) deadline)
          (return))
        (cond
          ((listen out)
           (let ((c (read-char-no-hang out nil :eof)))
             (cond ((eq c :eof) (return))
                   (c           (write-char c buf))
                   (t           (sleep 0.02)))))
          ((not (agent-alive-p))
           (loop while (listen out)
                 do (let ((c (read-char-no-hang out nil nil)))
                      (when c (write-char c buf))))
           (return))
          (t (sleep 0.05))))
      (setf *agent-process* nil)
      (string-trim '(#\Newline #\Return #\Space)
                   (get-output-stream-string buf)))))
