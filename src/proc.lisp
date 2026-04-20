(in-package #:photo-ai-lisp)

(defstruct child-process
  process   ; uiop:process-info
  stdin     ; writable stream → child stdin
  stdout)   ; readable stream ← child stdout (stderr merged in)

(defvar *conpty-bridge-path*
  (namestring (merge-pathnames "tools/conpty-bridge/conpty-bridge.exe"
                               (uiop:getcwd)))
  "Path to the ConPTY bridge binary. When present and runnable, Windows
   children are spawned through it so they see a real Pseudo Console
   (interactive CLIs like `claude` detect it and start a REPL; `set /p`
   echoes). Falls back to plain cmd.exe with piped stdio if the bridge
   isn't built. Build with:
     cd tools/conpty-bridge && go build -o conpty-bridge.exe .")

(defun %default-argv ()
  (cond
    ((and (uiop:os-windows-p)
          (uiop:file-exists-p *conpty-bridge-path*))
     (list *conpty-bridge-path* "cmd.exe"))
    ((uiop:os-windows-p)
     '("cmd.exe"))
    (t
     '("/bin/bash"))))

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
                                   :element-type    '(unsigned-byte 8))))
    (make-child-process
     :process proc
     :stdin   (uiop:process-info-input  proc)
     :stdout  (uiop:process-info-output proc))))

(defun child-alive-p (child)
  (uiop:process-alive-p (child-process-process child)))

(defun kill-child (child)
  (ignore-errors (close (child-process-stdin child)))
  (ignore-errors (uiop:terminate-process (child-process-process child))))
