(in-package #:photo-ai-lisp)

(defvar *agent-command* "claude"
  "Path or basename of the resident agent CLI. Must be on PATH.")

(defvar *agent-args* '("--dangerously-skip-permissions" "--model" "sonnet")
  "Arguments passed to *agent-command* on spawn.")

(defvar *agent-process* nil
  "uiop process-info for the currently running agent, or NIL.")

(defvar *agent-failures* 0
  "Consecutive respawn failures since the last healthy start.")

(defvar *agent-max-failures* 3
  "Stop auto-restarting after this many consecutive crashes.")

(defvar *agent-monitor-thread* nil)
(defvar *agent-monitor-stop* nil)
(defvar *agent-lock* (bordeaux-threads:make-lock "photo-ai-lisp.agent"))

(defun %spawn-agent ()
  (uiop:launch-program (cons *agent-command* *agent-args*)
                       :input :stream
                       :output :stream
                       :error-output :stream))

(defun agent-alive-p ()
  (and *agent-process* (uiop:process-alive-p *agent-process*)))

(defun agent-stdin ()  (and *agent-process* (uiop:process-info-input  *agent-process*)))
(defun agent-stdout () (and *agent-process* (uiop:process-info-output *agent-process*)))

(defun start-agent (&key (command nil command-supplied-p) (args nil args-supplied-p))
  "Spawn the agent subprocess if it is not already running."
  (when command-supplied-p (setf *agent-command* command))
  (when args-supplied-p    (setf *agent-args*    args))
  (bordeaux-threads:with-lock-held (*agent-lock*)
    (unless (agent-alive-p)
      (setf *agent-process*   (%spawn-agent)
            *agent-failures*  0
            *agent-monitor-stop* nil)
      (%ensure-monitor)))
  *agent-process*)

(defun stop-agent ()
  "Terminate the agent subprocess and the monitor thread."
  (bordeaux-threads:with-lock-held (*agent-lock*)
    (setf *agent-monitor-stop* t)
    (when *agent-process*
      (ignore-errors (close (agent-stdin)))
      (ignore-errors (uiop:terminate-process *agent-process*))
      (ignore-errors (uiop:wait-process *agent-process*))
      (setf *agent-process* nil)))
  (when (and *agent-monitor-thread*
             (bordeaux-threads:thread-alive-p *agent-monitor-thread*))
    (ignore-errors (bordeaux-threads:join-thread *agent-monitor-thread*)))
  (setf *agent-monitor-thread* nil)
  t)

(defun restart-agent ()
  (stop-agent)
  (start-agent))

(defun %ensure-monitor ()
  (when (and *agent-monitor-thread*
             (bordeaux-threads:thread-alive-p *agent-monitor-thread*))
    (return-from %ensure-monitor))
  (setf *agent-monitor-thread*
        (bordeaux-threads:make-thread #'%monitor-loop :name "photo-ai-lisp.agent-monitor")))

(defun %monitor-loop ()
  (loop
    (sleep 1)
    (bordeaux-threads:with-lock-held (*agent-lock*)
      (when *agent-monitor-stop* (return))
      (when (and *agent-process* (not (agent-alive-p)))
        (incf *agent-failures*)
        (cond
          ((>= *agent-failures* *agent-max-failures*)
           (format *error-output*
                   "~&[photo-ai-lisp.agent] ~D consecutive failures, giving up.~%"
                   *agent-failures*)
           (setf *agent-process* nil)
           (return))
          (t
           (format *error-output*
                   "~&[photo-ai-lisp.agent] restart ~D/~D after crash~%"
                   *agent-failures* *agent-max-failures*)
           (setf *agent-process* (%spawn-agent))))))))

(defun agent-send (msg &key (timeout-seconds 3))
  "Write MSG + newline to the agent's stdin, then drain available stdout
until there is no more data within TIMEOUT-SECONDS. Returns whatever was
read as a string. Returns empty string if the agent is not alive."
  (unless (agent-alive-p)
    (return-from agent-send ""))
  (let ((in  (agent-stdin))
        (out (agent-stdout)))
    (write-line msg in)
    (finish-output in)
    (let ((deadline (+ (get-internal-real-time)
                       (* timeout-seconds internal-time-units-per-second)))
          (buf (make-string-output-stream))
          (saw-any nil)
          (quiet-since nil))
      (loop
        (cond
          ((> (get-internal-real-time) deadline)
           (return (get-output-stream-string buf)))
          ((listen out)
           (let ((c (read-char-no-hang out nil nil)))
             (cond (c (write-char c buf)
                      (setf saw-any t quiet-since nil))
                   (t (return (get-output-stream-string buf))))))
          (t
           (when saw-any
             (unless quiet-since (setf quiet-since (get-internal-real-time)))
             (when (> (- (get-internal-real-time) quiet-since)
                      (* 0.3 internal-time-units-per-second))
               (return (get-output-stream-string buf))))
           (sleep 0.03)))))))
