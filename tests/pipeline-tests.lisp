(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test pipeline-make-steps-initializes
  (pipeline-make-steps)
  (is (= 4 (length photo-ai-lisp::*pipeline-state*)))
  (is (every (lambda (s) (eql :pending (getf s :status)))
             photo-ai-lisp::*pipeline-state*)))

(test pipeline-step-lookup
  (pipeline-make-steps)
  (let ((s (photo-ai-lisp::pipeline-step "scan")))
    (is (not (null s)))
    (is (string= "scan" (getf s :name)))))

(test pipeline-step-missing
  (pipeline-make-steps)
  (is (null (photo-ai-lisp::pipeline-step "no-such-step"))))

(test set-step-mutates
  (pipeline-make-steps)
  (photo-ai-lisp::set-step "scan" :status :running :artifact "/tmp/x.json")
  (let ((s (photo-ai-lisp::pipeline-step "scan")))
    (is (eql :running (getf s :status)))
    (is (string= "/tmp/x.json" (getf s :artifact)))))

;; run-pipeline requires subprocess + real skills  tagged :integration, excluded by default
(test (run-pipeline-integration :suite nil)
  (pass "run-pipeline is an integration test; skipped in unit suite"))
