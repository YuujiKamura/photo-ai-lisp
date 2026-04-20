(in-package #:photo-ai-lisp/tests)

;;; Observability tests. Two layers:
;;;   1. shell-trace-record / shell-trace-handler — pure in-memory ring,
;;;      testable without any WebSocket or subprocess.
;;;   2. cmd.exe / bash stdin→stdout round-trip via spawn-child — proves
;;;      the child really executes injected text. Runs on both OSes.

(5am:def-suite shell-trace-suite :description "shell observability")
(5am:in-suite shell-trace-suite)

(5am:test shell-trace-records-in-and-out
  (photo-ai-lisp::shell-trace-clear)
  (photo-ai-lisp::shell-trace-record :in  "echo hi")
  (photo-ai-lisp::shell-trace-record :out "hi")
  (let ((snap (photo-ai-lisp::shell-trace-snapshot)))
    (5am:is (= 2 (length snap)))
    ;; newest first
    (5am:is (eq :out (getf (first snap) :dir)))
    (5am:is (eq :in  (getf (second snap) :dir)))
    (5am:is (= 7 (getf (second snap) :bytes)))
    (5am:is (= 2 (getf (first snap) :bytes)))))

(5am:test shell-trace-ring-caps-at-max
  (photo-ai-lisp::shell-trace-clear)
  (let ((photo-ai-lisp::*shell-trace-max* 3))
    (dotimes (i 10)
      (photo-ai-lisp::shell-trace-record :in (format nil "msg-~a" i)))
    (5am:is (= 3 (length (photo-ai-lisp::shell-trace-snapshot))))))

(5am:test shell-trace-handler-returns-json
  (photo-ai-lisp::shell-trace-clear)
  (photo-ai-lisp::shell-trace-record :in "alpha")
  (let ((json (photo-ai-lisp::shell-trace-handler)))
    (5am:is (char= #\[ (char json 0)))
    (5am:is (char= #\] (char json (1- (length json)))))
    (5am:is (search "\"dir\":\"in\"" json))
    (5am:is (search "\"bytes\":5" json))
    (5am:is (search "\"preview\":\"alpha\"" json))))

(5am:test shell-trace-preview-scrubs-control-bytes
  (photo-ai-lisp::shell-trace-clear)
  (photo-ai-lisp::shell-trace-record :in (format nil "a~cb~cc" #\Return #\Newline))
  (let ((preview (getf (first (photo-ai-lisp::shell-trace-snapshot)) :preview)))
    (5am:is (search "a b c" preview))
    (5am:is (not (find #\Return preview)))
    (5am:is (not (find #\Newline preview)))))

;; ---- round trip through a real subprocess -------------------------------

(5am:def-suite shell-roundtrip-suite :description "stdin->stdout via real child")
(5am:in-suite shell-roundtrip-suite)

(defun %drain-until (stream needle timeout-seconds)
  "Read from STREAM into a string buffer until NEEDLE appears or
   TIMEOUT-SECONDS elapses. Returns the accumulated string (may or may
   not contain NEEDLE — caller checks)."
  (let ((buf (make-array 256 :element-type 'character
                              :adjustable t :fill-pointer 0))
        (deadline (+ (get-internal-real-time)
                     (* timeout-seconds internal-time-units-per-second))))
    (loop
      (cond
        ((listen stream)
         (let ((c (read-char stream nil :eof)))
           (when (eq c :eof) (return buf))
           (vector-push-extend c buf)
           (when (search needle buf)
             (return buf))))
        ((> (get-internal-real-time) deadline)
         (return buf))
        (t (sleep 0.02))))))

(5am:test cmd-or-bash-inject-echo-sentinel
  "Inject a sentinel command into a freshly spawned shell and verify the
   sentinel bytes come back out. Works on both Windows (cmd.exe) and
   Unix (bash). This is the 'was my command actually typed into the
   terminal?' question answered without a browser."
  (let* ((argv (if (uiop:os-windows-p)
                   '("cmd.exe")
                   '("/bin/bash" "--norc" "--noprofile")))
         (child (photo-ai-lisp::spawn-child argv))
         (sentinel (format nil "SENTINEL-~a" (random 100000))))
    (unwind-protect
        (let ((in  (photo-ai-lisp::child-process-stdin  child))
              (out (photo-ai-lisp::child-process-stdout child)))
          ;; Let the shell settle / print its banner
          (%drain-until out "__never__" 0.6)
          (write-string (format nil "echo ~a~%" sentinel) in)
          (finish-output in)
          (let ((observed (%drain-until out sentinel 3.0)))
            (5am:is (search sentinel observed)
                    "sentinel ~a not observed in stdout (got ~a chars)"
                    sentinel (length observed))))
      (photo-ai-lisp::kill-child child))))
