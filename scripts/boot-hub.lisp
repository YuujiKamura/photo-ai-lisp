;;;; scripts/boot-hub.lisp
;;;; T1.c — boot-hub smoke: connect, LIST, disconnect, exit 0.
;;;;
;;;; Usage:
;;;;   sbcl --script scripts/boot-hub.lisp
;;;;
;;;; Exit 0 on success, 1 on any error.

;;; GCA-1: Derive repo-root from *load-pathname* so the script works when
;;; invoked from any directory via `sbcl --script /path/to/scripts/boot-hub.lisp`.
;;; *load-pathname* is a standard CL variable — no package prefix needed before
;;; quicklisp is loaded.
(defvar *repo-root*
  (make-pathname :name nil :type nil :version nil
                 :defaults (merge-pathnames
                             (make-pathname :directory '(:relative :up))
                             (make-pathname :name nil :type nil :version nil
                                            :defaults (or *load-pathname* *default-pathname-defaults*)))))

(load "~/quicklisp/setup.lisp")
(push *repo-root* asdf:*central-registry*)
(ql:quickload :photo-ai-lisp :silent t)

(in-package #:photo-ai-lisp)

;;; GCA-2 helper: poll ready-state up to 2 s for :open.
(defun %wait-ws-open (driver &key (max-tries 20) (interval 0.1))
  "Return T when DRIVER's ready-state becomes :open, NIL on timeout."
  (loop repeat max-tries
        for state = (wsd:ready-state driver)
        when (eq state :open) return t
        do (sleep interval)
        finally (return nil)))

(handler-case
    (progn
      (format t "[BOOT] photo-ai-lisp hub smoke start~%")
      (let* ((client (connect-cp :port 8080))
             (driver (cp-client-driver client))
             (ready (and driver (%wait-ws-open driver))))
        ;; GCA-2: check actual WebSocket handshake, not just object creation.
        (unless ready
          (let ((state (and driver (wsd:ready-state driver))))
            (format *error-output* "[BOOT] CONNECT: FAIL (ready-state=~A)~%" state)
            (uiop:quit 1)))
        (format t "[BOOT] connect ws://127.0.0.1:8080/ws -> OK~%")

        ;; GCA-2: wrap blocking send-cp-command in a timeout to avoid hang.
        (let ((resp (bt:with-timeout (5)
                      (send-cp-command client (make-cp-list-tabs)))))
          (unless (getf resp :ok)
            (error "LIST returned non-ok: ~S" resp))
          (format t "[BOOT] LIST ok=T session-count=~A~%"
                  (length (getf resp :data))))
        (ignore-errors (disconnect-cp client)))
      (format t "[BOOT] ok~%")
      (uiop:quit 0))
  (bt:timeout ()
    (format *error-output* "[BOOT] FATAL: send-cp-command timed out after 5 s~%")
    (uiop:quit 1))
  (error (c)
    (format *error-output* "[BOOT] FATAL: ~A~%" c)
    (uiop:quit 1)))
