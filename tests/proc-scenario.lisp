(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test spawn-child-unix-echo
  (if (uiop:os-windows-p)
      (skip "spawn-child scenario: skipped on Windows")
      (let* ((child (photo-ai-lisp::spawn-child '("/bin/bash" "-c" "echo hello")))
             (output (with-output-to-string (s)
                       (loop for line = (read-line (photo-ai-lisp::child-process-stdout child) nil nil)
                             while line
                             do (write-string line s)))))
        (photo-ai-lisp::kill-child child)
        (is (search "hello" output)
            "spawn-child stdout should contain 'hello', got: ~s" output))))
