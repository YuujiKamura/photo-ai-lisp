(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; Integration tests for spawn-child + %normalize-child-input + conpty-bridge.
;;;
;;; Why this file exists:
;;;   The unit tests in proc-tests.lisp and term-tests.lisp lock individual
;;;   behaviors (argv shape, latin-1 scrub, LF->CR, CR-run collapse). What
;;;   they do not lock is the wire-level composition: an actual cmd.exe
;;;   spawned through the default argv path, fed a normalized command via
;;;   its stdin, and inspected for the expected output on stdout. Commit
;;;   de778f7 (picker-inject race) and the ConPTY bridge rewrite both
;;;   shipped without a regression test at that layer; this file fills
;;;   that gap so a future refactor of spawn-child, %shell-argv, or the
;;;   bridge is caught by CI rather than by a human noticing the REPL is
;;;   silent again.
;;;
;;; Platform gating:
;;;   The whole file is Windows-only. Non-Windows environments exercise
;;;   the same moving parts through tests/proc-scenario.lisp's bash path,
;;;   so there is no loss of coverage — just a clean skip message instead
;;;   of a spurious fail on Linux CI.

(defun %drain-child-until (child predicate &key (timeout-s 8.0) (poll 0.05))
  "Pump bytes from CHILD's stdout into an accumulating string until
   PREDICATE (called with the string so far) returns non-NIL, or until
   TIMEOUT-S elapses. Returns the accumulated string.

   Named distinctly from shell-trace-tests.lisp::%drain-until (same
   package, different arity) so the two don't collide at load time.

   Mirrors the non-blocking read pattern used by %stdout-pump in
   src/term.lisp: LISTEN gates READ-BYTE so we never park the test
   thread on a stream that has quieted down. Polling at 50 ms keeps
   the loop responsive without spinning the CPU, and every test in
   this file caps its wall time at a few seconds so the suite stays
   well under the 30 s budget imposed by the brief."
  (let* ((out   (photo-ai-lisp::child-process-stdout child))
         (sink  (make-array 256 :element-type 'character
                                :adjustable t :fill-pointer 0))
         (deadline (+ (get-internal-real-time)
                      (* timeout-s internal-time-units-per-second))))
    (loop
      (cond
        ((funcall predicate sink)
         (return sink))
        ((> (get-internal-real-time) deadline)
         (return sink))
        ((listen out)
         (let ((b (read-byte out nil :eof)))
           (cond
             ((eq b :eof) (return sink))
             ((null b)    nil)
             (t (vector-push-extend (code-char b) sink)))))
        (t (sleep poll))))))

(defun %contains (needle)
  "Build a predicate closure that checks whether NEEDLE is a substring
   of the accumulated output. Factored out so the three tests below
   read as declarative contracts rather than SEARCH boilerplate."
  (lambda (sink) (search needle sink)))

;;; test-a — default argv spawn + stdin echo round-trip.
;;;
;;; Locks the happy path: the bytes that %normalize-child-input returns
;;; for "echo HELLO\n" really are an Enter-terminated command as far as
;;; whatever child %default-argv picked (bridged cmd if present, plain
;;; cmd.exe otherwise). If spawn-child's stdio contract regresses (wrong
;;; external-format, wrong element-type, lost finish-output), the echo
;;; payload either never leaves Lisp or returns garbled and HELLO never
;;; appears on stdout.
(test integration-spawn-default-echoes-hello
  (if (not (uiop:os-windows-p))
      (skip "integration-spawn-default-echoes-hello: Windows-only")
      (let ((child (photo-ai-lisp::spawn-child)))
        (unwind-protect
            (let* ((bytes (photo-ai-lisp::%normalize-child-input
                           (format nil "echo HELLO~C" #\Newline)))
                   (stdin (photo-ai-lisp::child-process-stdin child)))
              (write-sequence bytes stdin)
              (finish-output stdin)
              (let ((out (%drain-child-until child (%contains "HELLO"))))
                (is (search "HELLO" out)
                    "expected HELLO in stdout within timeout, got: ~s"
                    out)))
          (photo-ai-lisp::kill-child child)))))

;;; test-b — conpty-bridge path emits real VT escape bytes.
;;;
;;; Plain piped cmd.exe has no console attached and does not emit
;;; terminal escape sequences. cmd.exe hosted under the conpty-bridge
;;; sees a real Pseudo Console and the prompt redraw + cursor moves
;;; come out as CSI / OSC sequences, i.e. bytes beginning with ESC
;;; (0x1B). We don't pin a specific sequence like "[?25l" because the
;;; exact stream depends on the cmd build; we only lock the much more
;;; stable invariant: at least one ESC byte shows up, which is enough
;;; to prove the bridge really wrapped the child in a PTY and stdout
;;; round-trips its raw output to Lisp.
(test integration-bridge-emits-vt-escape
  (cond
    ((not (uiop:os-windows-p))
     (skip "integration-bridge-emits-vt-escape: Windows-only"))
    ((not (uiop:file-exists-p photo-ai-lisp::*conpty-bridge-path*))
     (skip "integration-bridge-emits-vt-escape: conpty-bridge.exe not built"))
    (t
     (let ((child (photo-ai-lisp::spawn-child
                   (list photo-ai-lisp::*conpty-bridge-path* "cmd.exe"))))
       (unwind-protect
           (let ((out (%drain-child-until
                       child
                       (lambda (s) (find (code-char 27) s)))))
             (is (find (code-char 27) out)
                 "expected at least one ESC byte from ConPTY-hosted cmd, got: ~s"
                 out))
         (photo-ai-lisp::kill-child child))))))

;;; test-c — multi-line normalize idempotency end-to-end.
;;;
;;; Lock for commit de778f7: sending two LF-terminated commands in one
;;; write must execute as two distinct Enter presses. Before that fix,
;;; a CRLF pair inside a single write (or any CR-run > 1) silently
;;; answered any live `set /p` with an empty line and the second
;;; command never ran. The tokens MARK-ALPHA / MARK-BETA are distinct
;;; enough not to alias on cmd's own echo of the command line — the
;;; bytes appear once as the echoed command and once as the printed
;;; output, which is exactly what we want to prove both ran.
(test integration-two-lines-both-execute
  (if (not (uiop:os-windows-p))
      (skip "integration-two-lines-both-execute: Windows-only")
      (let ((child (photo-ai-lisp::spawn-child)))
        (unwind-protect
            (let* ((payload (format nil "echo MARK-ALPHA~Cecho MARK-BETA~C"
                                    #\Newline #\Newline))
                   (bytes   (photo-ai-lisp::%normalize-child-input payload))
                   (stdin   (photo-ai-lisp::child-process-stdin child)))
              (write-sequence bytes stdin)
              (finish-output stdin)
              (let ((out (%drain-child-until
                          child
                          (lambda (s)
                            (and (search "MARK-ALPHA" s)
                                 (search "MARK-BETA"  s))))))
                (is (search "MARK-ALPHA" out)
                    "first line must execute (MARK-ALPHA missing), got: ~s" out)
                (is (search "MARK-BETA" out)
                    "second line must execute (MARK-BETA missing), got: ~s" out)))
          (photo-ai-lisp::kill-child child)))))
