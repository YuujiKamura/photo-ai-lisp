(in-package #:photo-ai-lisp)

(defstruct child-process
  process   ; uiop:process-info
  stdin     ; writable stream → child stdin
  stdout)   ; readable stream ← child stdout (stderr merged in)

(defun %default-argv ()
  (if (uiop:os-windows-p)
      '("cmd.exe")
      '("/bin/bash")))

(defparameter %inherited-env-whitelist%
  '("PATH" "SYSTEMROOT" "USERPROFILE" "TEMP" "TMP"
    "WINDIR" "COMSPEC" "HOME" "LANG" "LC_ALL" "LC_CTYPE"))

(defun %compose-environment (extra)
  (let ((normalized-extra
          (loop for entry in extra
                collect (typecase entry
                          (cons entry)
                          (string (let ((eq-pos (position #\= entry)))
                                    (if eq-pos
                                        (cons (subseq entry 0 eq-pos)
                                              (subseq entry (1+ eq-pos)))
                                        (cons entry ""))))
                          (t (error "Unsupported environment entry: ~s" entry))))))
    (append (loop for (name . value) in normalized-extra
                  collect (format nil "~a=~a" name value))
            (loop with seen = (mapcar #'car normalized-extra)
                  for name in %inherited-env-whitelist%
                  for value = (uiop:getenv name)
                  when (and value
                            (not (member name seen :test #'string-equal)))
                    collect (format nil "~a=~a" name value)))))

(defun spawn-child (&optional (argv (%default-argv)) &key directory environment)
  "Launch ARGV as a subprocess with piped stdio.
Returns a CHILD-PROCESS; stderr is merged into stdout.

When ENVIRONMENT is non-NIL, it is composed on top of a small inherited
whitelist before forwarding to UIOP. When ENVIRONMENT is NIL, no
:ENVIRONMENT keyword is passed so the existing default inheritance path
remains byte-identical.

External-format is forced to LATIN-1 so the stdout byte stream is decoded
lossy-but-totally byte-safe; otherwise SBCL's default UTF-8 decoder can hit
OEM codepage bytes (e.g. cmd.exe output on Japanese Windows) and either
signal or return NIL from READ-CHAR, which used to crash the stdout pump
thread and tear down the shell WebSocket on the first keystroke."
  (let* ((composed-environment (when environment
                                 (%compose-environment environment)))
         (launch-args (append (list argv
                                    :input           :stream
                                    :output          :stream
                                    :error-output    :output
                                    :element-type    'character
                                    :external-format :latin-1)
                              (when directory
                                (list :directory directory))
                              (when composed-environment
                                (list :environment composed-environment))))
         (proc (apply #'uiop:launch-program launch-args)))
    (make-child-process
     :process proc
     :stdin   (uiop:process-info-input  proc)
     :stdout  (uiop:process-info-output proc))))

(defun child-alive-p (child)
  (uiop:process-alive-p (child-process-process child)))

(defun kill-child (child)
  (ignore-errors (close (child-process-stdin child)))
  (ignore-errors (uiop:terminate-process (child-process-process child))))
