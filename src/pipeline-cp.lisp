(in-package #:photo-ai-lisp)

;;; Issue #17 — Pipeline CP Bridge.
;;; Provides a way to run skills via the Control Plane.

(defun invoke-via-cp (client skill-name &key input)
  "Sends SKILL-NAME and INPUT to the CP client, waits for completion,
   and returns (values output-plist success-p).
   Protocol:
     -> INPUT|photo-ai-lisp|base64(/run :skill-name input-plist)
     <- ... DONE|:skill-name|output-plist
     <- ... ERROR|:skill-name|message"
  (let ((cmd (format nil "/run ~A ~S" skill-name input)))
    (cp-input client cmd)
    (loop for i from 1 to 50 ; max 5 seconds (50 * 0.1s)
          for lines = (cp-tail client :n 10)
          for done-line = (find-if (lambda (l)
                                     (and (stringp l)
                                          (search (format nil "DONE|~A|" skill-name) l)))
                                   lines)
          for err-line = (find-if (lambda (l)
                                    (and (stringp l)
                                         (search (format nil "ERROR|~A|" skill-name) l)))
                                  lines)
          do (cond (done-line
                    (let* ((prefix (format nil "DONE|~A|" skill-name))
                           (payload (subseq done-line (length prefix))))
                      (return-from invoke-via-cp
                        (values (read-from-string payload) t))))
                   (err-line
                    (warn "Skill ~A failed: ~A" skill-name err-line)
                    (return-from invoke-via-cp (values nil nil)))
                   (t (sleep 0.1)))
          finally (progn
                    (warn "Skill ~A timed out after 5 seconds" skill-name)
                    (return (values nil nil))))))
