(in-package #:photo-ai-lisp)

;;; Policy directive #02 — minimum viable pipeline DSL.
;;;
;;; This file currently contains STUBS only. Every symbol is defined so
;;; `tests/pipeline-tests.lisp` can load, but behaviour signals
;;; UNIMPLEMENTED until the atoms under `.dispatch/codex-pipeline-*.md`
;;; land. The test suite is intentionally red on this branch until the
;;; implementation lands.
;;;
;;; Reuses `unimplemented` condition + `%unimpl` helper from case.lisp.

;; ---- skill registry ------------------------------------------------------

(defvar *skills* (make-hash-table :test #'eq)
  "Keyword skill name -> SKILL instance. The wiring layer between
   pipeline steps (pure data) and external subprocess invocations.")

(defclass skill ()
  ((name     :initarg :name     :reader skill-name
             :initform nil
             :documentation "Keyword identifying this skill, e.g. :scan.")
   (describe :initarg :describe :reader skill-describe
             :initform ""
             :documentation "Short human-readable summary.")
   (invoke   :initarg :invoke   :reader skill-invoke
             :initform nil
             :documentation "Function (input-plist) -> (values output-plist success-p).
                             Tests inject pure-function invokers; production
                             skills wrap uiop:run-program."))
  (:documentation "One step in the pipeline DSL. Pure data object; the
                   real work lives in the INVOKE thunk."))

(defun make-skill (&key name describe invoke)
  (make-instance 'skill :name name :describe describe :invoke invoke))
(defun register-skill (name &key describe invoke)
  "Create or replace a SKILL under NAME in *skills*. Returns the skill."
  (let ((s (make-skill :name name :describe describe :invoke invoke)))
    (setf (gethash name *skills*) s)
    s))

(defun find-skill (name)
  "Return the SKILL for NAME, or NIL."
  (gethash name *skills*))

(defun unregister-skill (name)
  "Remove NAME from *skills*. Idempotent."
  (remhash name *skills*))

;; ---- pipeline registry + compilation -------------------------------------

(defvar *pipelines* (make-hash-table :test #'eq)
  "Symbol pipeline name -> PIPELINE instance.")

(defclass pipeline ()
  ((name  :initarg :name  :reader pipeline-name
          :initform nil
          :documentation "Symbol identifier for this pipeline.")
   (steps :initarg :steps :reader pipeline-steps
          :initform nil
          :documentation "Ordered list of step specs. Each step is
                          (:skill-name &rest per-step-kwargs). Skill
                          resolution happens at run time — steps keep
                          the symbolic name, not the SKILL object."))
  (:documentation "A compiled pipeline. Data-only; DEFPIPELINE creates it."))

(defmacro defpipeline (name &body steps)
  "Compile STEPS into a PIPELINE and register it under NAME in *pipelines*.
   Each step is a list whose first element is a keyword skill name.

   Example:
     (defpipeline standard-case-run
       (:scan)
       (:infer-scope)
       (:match :priority '(工種 種別))
       (:export-xlsx))"
  (declare (ignore name steps))
  `(progn
     (%unimpl 'defpipeline)))

(defun find-pipeline (name)
  "Return the PIPELINE for NAME, or NIL."
  (declare (ignore name))
  (%unimpl 'find-pipeline))

;; ---- executor ------------------------------------------------------------

(defclass pipeline-result ()
  ((success-p     :initarg :success-p     :reader pipeline-result-success-p
                  :initform nil
                  :documentation "T if every step's invoke returned success.")
   (steps         :initarg :steps         :reader pipeline-result-steps
                  :initform nil
                  :documentation "List of plists, one per step executed:
                                  (:name <keyword> :output <plist>
                                   :success-p <bool>).")
   (final-output  :initarg :final-output  :reader pipeline-result-final-output
                  :initform nil
                  :documentation "Output plist from the last step that ran.")
   (failure-index :initarg :failure-index :reader pipeline-result-failure-index
                  :initform nil
                  :documentation "0-based index of the first failing step,
                                  or NIL on full success.")))

(defun run-pipeline (pipeline-or-name &key input)
  "Execute the pipeline with INPUT (plist, default NIL). Thread each step's
   output into the next step's input. Halt on the first failing step and
   record the failure index. Return a PIPELINE-RESULT."
  (declare (ignore pipeline-or-name input))
  (%unimpl 'run-pipeline))
