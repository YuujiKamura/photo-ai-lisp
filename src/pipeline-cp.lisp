(in-package #:photo-ai-lisp)

;;; Issue #17 — Pipeline CP Bridge.
;;; Provides a way to run skills via the Control Plane.

(defun invoke-via-cp (client skill-name &key input session-id)
  "Sends SKILL-NAME and INPUT to the CP client, waits for completion,
   and returns (values output success-p).
   Supports both JSON (wait for idle) and legacy pipe (DONE| marker) modes."
  (let* ((cmd (format nil "/run ~A ~S" skill-name input))
         (resp (cp-input client cmd :session-id session-id)))
    ;; Check if we are in JSON mode or legacy mode
    (cond ((and (listp resp) (getf resp :ok))
           ;; JSON mode: poll for idle status
           (if (wait-for-completion client session-id :timeout 50 :interval 1)
               (values nil t)
               (progn (warn "Skill ~A timed out (JSON mode)" skill-name)
                      (values nil nil))))
          (t
           ;; Legacy or fallback: poll for DONE| marker in tail
           (loop repeat 50
                 for lines = (cp-tail client :n 10 :session-id session-id)
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
                           (warn "Skill ~A failed (legacy mode): ~A" skill-name err-line)
                           (return-from invoke-via-cp (values nil nil)))
                          (t (sleep 0.1)))
                 finally (progn
                           (warn "Skill ~A timed out (legacy mode)" skill-name)
                           (return (values nil nil))))))))
