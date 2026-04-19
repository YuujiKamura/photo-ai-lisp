(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test spawn-child-unix-echo
  (if (uiop:os-windows-p)
      (skip "spawn-child scenario: skipped on Windows")
      (let* ((child (photo-ai-lisp::spawn-child :argv '("/bin/bash" "-c" "echo hello")))
             (output (with-output-to-string (s)
                       (loop for line = (read-line (photo-ai-lisp::child-process-stdout child) nil nil)
                             while line
                             do (write-string line s)))))
        (photo-ai-lisp::kill-child child)
        (is (search "hello" output)
            "spawn-child stdout should contain 'hello', got: ~s" output))))

;;; 2e — interactive stdin→stdout round-trip through bash.
(test shell-echo-round-trip
  (if (uiop:os-windows-p)
      (skip "shell round-trip: skipped on Windows")
      (let ((child (photo-ai-lisp::spawn-child
                    :argv '("/bin/bash" "--norc" "--noprofile"))))
        (unwind-protect
            (let ((in  (photo-ai-lisp::child-process-stdin  child))
                  (out (photo-ai-lisp::child-process-stdout child)))
              (write-string (format nil "echo hi~%") in)
              (finish-output in)
              (close in)
              (let ((output (with-output-to-string (s)
                              (loop for line = (read-line out nil nil)
                                    while line
                                    do (write-string line s)))))
                (is (search "hi" output)
                    "shell echo round-trip should produce 'hi', got: ~s" output)))
          (photo-ai-lisp::kill-child child)))))
