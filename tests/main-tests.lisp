(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT3 — unit tests for src/main.lisp
;;; Tests *acceptor* state transitions and start/stop function contracts.
;;; Actual network listen is out of scope; tests use dynamic binding to
;;; exercise code paths that do not touch the network.

;; UT3a: *acceptor* defvar is accessible and initially nil (or bound).
(test main-acceptor-defvar-exists
  (is-true (boundp 'photo-ai-lisp::*acceptor*)
           "*acceptor* defvar should be bound"))

;; UT3b: start returns existing *acceptor* when it is already set (idempotent).
;;  Binding *acceptor* to a sentinel prevents any real hunchentoot:start call.
(test main-start-idempotent-when-acceptor-set
  (let* ((sentinel (make-instance 'photo-ai-lisp::ws-easy-acceptor :port 19991))
         (photo-ai-lisp::*acceptor* sentinel))
    (let ((result (photo-ai-lisp::start)))
      (is (eq result sentinel)
          "start should return the existing *acceptor* without creating a new one"))))

;; UT3c: start accepts :port keyword without error when *acceptor* is pre-set.
(test main-start-accepts-port-keyword
  (let* ((sentinel (make-instance 'photo-ai-lisp::ws-easy-acceptor :port 19992))
         (photo-ai-lisp::*acceptor* sentinel))
    (finishes (photo-ai-lisp::start :port 9999))
    (is (eq sentinel photo-ai-lisp::*acceptor*)
        "start :port with existing *acceptor* should not replace it")))

;; UT3d: stop is a no-op (no error) when *acceptor* is nil.
(test main-stop-safe-with-nil-acceptor
  (let ((photo-ai-lisp::*acceptor* nil))
    (finishes (photo-ai-lisp::stop))
    (is (null photo-ai-lisp::*acceptor*)
        "stop with nil *acceptor* should leave it nil")))

;; UT3e: start → stop lifecycle clears *acceptor*.
;;  Uses a high ephemeral port (18543) to avoid conflicts.
;;  An unwind-protect guarantees the port is freed even if assertions fail.
(test main-lifecycle-stop-clears-acceptor
  (let ((saved photo-ai-lisp::*acceptor*))
    (unwind-protect
        (progn
          (setf photo-ai-lisp::*acceptor* nil)
          (photo-ai-lisp::start :port 18543)
          (is-true photo-ai-lisp::*acceptor*
                   "start should set *acceptor* to a non-nil value")
          (photo-ai-lisp::stop)
          (is (null photo-ai-lisp::*acceptor*)
              "stop should set *acceptor* to nil"))
      ;; Restore: stop any leftover acceptor, then put back saved value.
      (ignore-errors
        (when photo-ai-lisp::*acceptor*
          (hunchentoot:stop photo-ai-lisp::*acceptor*)))
      (setf photo-ai-lisp::*acceptor* saved))))

;; UT3f: start → stop → start sequence leaves *acceptor* set again.
(test main-start-stop-start-lifecycle
  (let ((saved photo-ai-lisp::*acceptor*))
    (unwind-protect
        (progn
          (setf photo-ai-lisp::*acceptor* nil)
          (photo-ai-lisp::start :port 18544)
          (photo-ai-lisp::stop)
          (is (null photo-ai-lisp::*acceptor*)
              "after stop, *acceptor* should be nil")
          (photo-ai-lisp::start :port 18544)
          (is-true photo-ai-lisp::*acceptor*
                   "second start should set *acceptor* again"))
      (ignore-errors
        (when photo-ai-lisp::*acceptor*
          (hunchentoot:stop photo-ai-lisp::*acceptor*)))
      (setf photo-ai-lisp::*acceptor* saved))))
