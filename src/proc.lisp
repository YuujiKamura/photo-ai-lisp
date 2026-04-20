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
External format is forced to :latin-1 so every byte maps to exactly one
character. This avoids UTF-8 decode failures in the stdout pump when
the child (e.g. cmd.exe) emits code-page-specific bytes."
  (let ((proc (uiop:launch-program argv
                                   :input           :stream
                                   :output          :stream
                                   :error-output    :output
                                   :element-type    'character
                                   :external-format :latin-1)))
    (make-child-process
     :process proc
     :stdin   (uiop:process-info-input  proc)
     :stdout  (uiop:process-info-output proc))))

(defun child-alive-p (child)
  (uiop:process-alive-p (child-process-process child)))

(defun kill-child (child)
  (ignore-errors (close (child-process-stdin child)))
  (ignore-errors (uiop:terminate-process (child-process-process child))))
