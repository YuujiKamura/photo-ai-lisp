(in-package #:photo-ai-lisp/tests)

;;; Policy directive #02 — spec-as-tests for src/pipeline.lisp.
;;;
;;; These deftests define the acceptance for the pipeline DSL
;;; (skill registry + defpipeline macro + run-pipeline executor).
;;; Every function body under src/pipeline.lisp currently signals
;;; UNIMPLEMENTED, so the tests here land red. RED is the spec.

(in-suite photo-ai-lisp-tests)

;;; ========================================================================
;;; Class shape + direct construction (should already be green via stubs)
;;; ========================================================================

(test pipeline-skill-class-exists
  (is-true (find-class 'photo-ai-lisp:skill nil)
           "photo-ai-lisp:skill must be a defined class"))

(test pipeline-make-skill-stores-slots
  (let ((s (photo-ai-lisp:make-skill
            :name :scan
            :describe "scan photos"
            :invoke (lambda (input) (values input t)))))
    (is (eq :scan (photo-ai-lisp:skill-name s)))
    (is (equal "scan photos" (photo-ai-lisp:skill-describe s)))
    (is (functionp (photo-ai-lisp:skill-invoke s)))))

(test pipeline-class-exists
  (is-true (find-class 'photo-ai-lisp:pipeline nil)))

(test pipeline-result-class-exists
  (is-true (find-class 'photo-ai-lisp:pipeline-result nil)))

;;; ========================================================================
;;; Skill registry CRUD
;;; ========================================================================

(test pipeline-register-then-find
  (photo-ai-lisp:unregister-skill :spec-tmp-reg)
  (let ((s (photo-ai-lisp:register-skill
            :spec-tmp-reg
            :describe "tmp"
            :invoke (lambda (in) (values in t)))))
    (is-true (typep s 'photo-ai-lisp:skill))
    (is (eq s (photo-ai-lisp:find-skill :spec-tmp-reg)))
    (photo-ai-lisp:unregister-skill :spec-tmp-reg)))

(test pipeline-find-skill-missing-returns-nil
  (photo-ai-lisp:unregister-skill :spec-missing)
  (is (null (photo-ai-lisp:find-skill :spec-missing))))

(test pipeline-register-skill-overwrites
  (photo-ai-lisp:unregister-skill :spec-over)
  (photo-ai-lisp:register-skill :spec-over :describe "v1"
                                :invoke (lambda (in) (values in t)))
  (photo-ai-lisp:register-skill :spec-over :describe "v2"
                                :invoke (lambda (in) (values in t)))
  (is (equal "v2" (photo-ai-lisp:skill-describe
                   (photo-ai-lisp:find-skill :spec-over))))
  (photo-ai-lisp:unregister-skill :spec-over))

(test pipeline-unregister-is-idempotent
  (photo-ai-lisp:unregister-skill :spec-none)
  (photo-ai-lisp:unregister-skill :spec-none)
  (is (null (photo-ai-lisp:find-skill :spec-none))))

;;; ========================================================================
;;; defpipeline macro + registry
;;; ========================================================================

(test pipeline-defpipeline-registers-under-name
  (photo-ai-lisp:defpipeline spec-empty-pipe)
  (is-true (typep (photo-ai-lisp:find-pipeline 'spec-empty-pipe)
                  'photo-ai-lisp:pipeline)))

(test pipeline-defpipeline-stores-steps-in-order
  (photo-ai-lisp:defpipeline spec-ordered-pipe
    (:a)
    (:b)
    (:c))
  (let ((p (photo-ai-lisp:find-pipeline 'spec-ordered-pipe)))
    (is (equal '(:a :b :c)
               (mapcar #'first (photo-ai-lisp:pipeline-steps p)))
        "pipeline-steps must preserve declaration order")))

(test pipeline-defpipeline-captures-step-args
  (photo-ai-lisp:defpipeline spec-args-pipe
    (:match :priority '(工種 種別)))
  (let* ((p    (photo-ai-lisp:find-pipeline 'spec-args-pipe))
         (step (first (photo-ai-lisp:pipeline-steps p))))
    (is (eq :match (first step)))
    (is (member :priority step)
        "step spec must carry the :priority kwarg the user wrote")))

(test pipeline-find-pipeline-missing-returns-nil
  (is (null (photo-ai-lisp:find-pipeline 'spec-nonexistent-pipeline))))

;;; ========================================================================
;;; Executor — run-pipeline
;;; ========================================================================

(defun %pipe-reset (&rest skill-keys)
  (dolist (k skill-keys) (photo-ai-lisp:unregister-skill k)))

(test pipeline-run-empty-pipeline-returns-success
  (photo-ai-lisp:defpipeline spec-run-empty)
  (let ((r (photo-ai-lisp:run-pipeline 'spec-run-empty :input '(:foo 1))))
    (is-true (typep r 'photo-ai-lisp:pipeline-result))
    (is-true (photo-ai-lisp:pipeline-result-success-p r))
    (is (null (photo-ai-lisp:pipeline-result-steps r)))
    (is (null (photo-ai-lisp:pipeline-result-failure-index r)))))

(test pipeline-run-single-step-invokes-skill
  (%pipe-reset :spec-single)
  (let ((calls '()))
    (photo-ai-lisp:register-skill :spec-single
                                  :invoke (lambda (input)
                                            (push input calls)
                                            (values (list :scanned t) t)))
    (photo-ai-lisp:defpipeline spec-run-single (:spec-single))
    (let ((r (photo-ai-lisp:run-pipeline 'spec-run-single :input '(:dir "/x"))))
      (is-true (photo-ai-lisp:pipeline-result-success-p r))
      (is (= 1 (length calls))
          "the skill invoke function must be called exactly once")
      (is (equal '(:dir "/x") (first calls))
          "invoke must receive the pipeline input")
      (is (equal '(:scanned t)
                 (photo-ai-lisp:pipeline-result-final-output r)))))
  (%pipe-reset :spec-single))

(test pipeline-run-threads-output-into-next-input
  (%pipe-reset :spec-stepA :spec-stepB)
  (photo-ai-lisp:register-skill :spec-stepA
                                :invoke (lambda (in)
                                          (declare (ignore in))
                                          (values '(:from-a 42) t)))
  (photo-ai-lisp:register-skill :spec-stepB
                                :invoke (lambda (in)
                                          (values (append in '(:from-b 7)) t)))
  (photo-ai-lisp:defpipeline spec-run-two (:spec-stepA) (:spec-stepB))
  (let* ((r      (photo-ai-lisp:run-pipeline 'spec-run-two))
         (final  (photo-ai-lisp:pipeline-result-final-output r)))
    (is-true (photo-ai-lisp:pipeline-result-success-p r))
    (is (equal 42 (getf final :from-a))
        "stepA output must be threaded into stepB")
    (is (equal 7  (getf final :from-b))))
  (%pipe-reset :spec-stepA :spec-stepB))

(test pipeline-run-records-per-step-results
  (%pipe-reset :spec-rec-A :spec-rec-B)
  (photo-ai-lisp:register-skill :spec-rec-A
                                :invoke (lambda (in)
                                          (declare (ignore in))
                                          (values '(:a 1) t)))
  (photo-ai-lisp:register-skill :spec-rec-B
                                :invoke (lambda (in)
                                          (values (append in '(:b 2)) t)))
  (photo-ai-lisp:defpipeline spec-run-rec (:spec-rec-A) (:spec-rec-B))
  (let ((steps (photo-ai-lisp:pipeline-result-steps
                (photo-ai-lisp:run-pipeline 'spec-run-rec))))
    (is (= 2 (length steps)))
    (is (eq :spec-rec-A (getf (first steps)  :name)))
    (is (eq :spec-rec-B (getf (second steps) :name)))
    (is-true (getf (first steps) :success-p))
    (is-true (getf (second steps) :success-p)))
  (%pipe-reset :spec-rec-A :spec-rec-B))

(test pipeline-run-halts-on-step-failure
  (%pipe-reset :spec-halt-A :spec-halt-B :spec-halt-C)
  (let ((b-ran nil))
    (photo-ai-lisp:register-skill :spec-halt-A
                                  :invoke (lambda (in)
                                            (declare (ignore in))
                                            (values '(:ok t) t)))
    (photo-ai-lisp:register-skill :spec-halt-B
                                  :invoke (lambda (in)
                                            (declare (ignore in))
                                            (values '(:err "fail") nil)))
    (photo-ai-lisp:register-skill :spec-halt-C
                                  :invoke (lambda (in)
                                            (declare (ignore in))
                                            (setf b-ran t)
                                            (values in t)))
    (photo-ai-lisp:defpipeline spec-run-halt
      (:spec-halt-A) (:spec-halt-B) (:spec-halt-C))
    (let ((r (photo-ai-lisp:run-pipeline 'spec-run-halt)))
      (is (null (photo-ai-lisp:pipeline-result-success-p r)))
      (is (= 1 (photo-ai-lisp:pipeline-result-failure-index r))
          "failure-index must be 0-based, pointing at :spec-halt-B")
      (is (null b-ran)
          "step C must not be invoked after B fails")
      (is (= 2 (length (photo-ai-lisp:pipeline-result-steps r)))
          "result-steps must include only the steps that ran (A and B)")))
  (%pipe-reset :spec-halt-A :spec-halt-B :spec-halt-C))

(test pipeline-run-unknown-skill-fails-cleanly
  (photo-ai-lisp:defpipeline spec-run-unknown (:spec-does-not-exist))
  (let ((r (photo-ai-lisp:run-pipeline 'spec-run-unknown)))
    (is (null (photo-ai-lisp:pipeline-result-success-p r))
        "missing skill must surface as a non-success run, not a raised error")
    (is (= 0 (photo-ai-lisp:pipeline-result-failure-index r)))))

(test pipeline-run-accepts-pipeline-object-directly
  (%pipe-reset :spec-obj)
  (photo-ai-lisp:register-skill :spec-obj
                                :invoke (lambda (in)
                                          (declare (ignore in))
                                          (values '(:x 1) t)))
  (photo-ai-lisp:defpipeline spec-run-obj (:spec-obj))
  (let* ((p (photo-ai-lisp:find-pipeline 'spec-run-obj))
         (r (photo-ai-lisp:run-pipeline p)))
    (is-true (photo-ai-lisp:pipeline-result-success-p r)
             "run-pipeline must accept a PIPELINE object, not just a symbol"))
  (%pipe-reset :spec-obj))
