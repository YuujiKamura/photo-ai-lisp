(in-package #:photo-ai-lisp)

;;; Issue #17 — Pipeline CP Bridge.
;;; Provides a way to run skills via the Control Plane.

(defun invoke-via-cp (client skill-name &key input)
  "Sends SKILL-NAME and INPUT to the CP client, waits for completion,
   and returns (values output-plist success-p)."
  (declare (ignore client skill-name input))
  (%unimpl 'invoke-via-cp))
