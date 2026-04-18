(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

(test screen-scenario-hello-world-via-parser
  (let* ((parser (photo-ai-lisp:make-parser))
         (screen (photo-ai-lisp:make-screen 5 10))
         (events (photo-ai-lisp:parser-feed-string
                  parser
                  (format nil "Hello~C~CWorld" #\Return #\Linefeed))))
    (dolist (event events)
      (photo-ai-lisp:apply-event screen event))
    (let ((snapshot (photo-ai-lisp:screen->text screen)))
      (is (search "Hello" snapshot))
      (is (search "World" snapshot)))))
