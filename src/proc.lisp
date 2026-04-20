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
  "Launch ARGV as a subprocess with piped stdio; stderr merged into stdout.
Returns a CHILD-PROCESS.

Stream contract (SBCL/Windows, verified):
  - stream-element-type is CHARACTER. uiop forwards :element-type to
    sb-ext:run-program but SBCL does not honor it for the :stream case;
    the internal pipe stream is hardcoded to :element-type :default,
    which is CHARACTER on SBCL. Declaring '(unsigned-byte 8) here was
    a no-op and has been removed.
  - :external-format :latin-1 is the load-bearing setting. Latin-1 is
    bijective over 0x00-0xFF, so no decode failure can tear the stdout
    pump when cmd.exe emits CP932/CP437/ISO-8859 bytes. Without this,
    the implicit :default external format resolves to :utf-8 on modern
    Windows SBCL and a single non-ASCII byte can crash the reader.
  - Callers rely on SBCL fd-stream bivalence: read-byte / write-sequence
    of byte vectors work on these CHARACTER streams even though the
    declared element-type is CHARACTER. This is an SBCL implementation
    detail, not an ANSI guarantee."
  (let ((proc (uiop:launch-program argv
                                   :input           :stream
                                   :output          :stream
                                   :error-output    :output
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
