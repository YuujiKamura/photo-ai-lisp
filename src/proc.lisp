(in-package #:photo-ai-lisp)

(defstruct child-process
  process   ; uiop:process-info
  stdin     ; writable stream → child stdin
  stdout)   ; readable stream ← child stdout (stderr merged in)

(defun %default-argv ()
  (if (uiop:os-windows-p)
      '("cmd.exe")
      '("/bin/bash")))

(defun spawn-child (&optional (argv (%default-argv)))
  "Launch ARGV as a subprocess with piped stdio.
Returns a CHILD-PROCESS; stderr is merged into stdout.

External-format is forced to LATIN-1 so the stdout byte stream is decoded
lossy-but-totally byte-safe; otherwise SBCL's default UTF-8 decoder can hit
OEM codepage bytes (e.g. cmd.exe output on Japanese Windows) and either
signal or return NIL from READ-CHAR, which used to crash the stdout pump
thread and tear down the shell WebSocket on the first keystroke."
  (let ((proc (uiop:launch-program argv
                                   :input              :stream
                                   :output             :stream
                                   :error-output       :output
                                   :element-type       'character
                                   :external-format    :latin-1)))
    (make-child-process
     :process proc
     :stdin   (uiop:process-info-input  proc)
     :stdout  (uiop:process-info-output proc))))

(defun child-alive-p (child)
  (uiop:process-alive-p (child-process-process child)))

(defun kill-child (child)
  (ignore-errors (close (child-process-stdin child)))
  (ignore-errors (uiop:terminate-process (child-process-process child))))
