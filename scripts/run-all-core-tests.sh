#!/bin/bash
export PATH="/c/Users/yuuji/SBCLLocal/PFiles/Steel Bank Common Lisp:$PATH"
sbcl --non-interactive \
     --load ~/quicklisp/setup.lisp \
     --eval '(push (uiop:getcwd) asdf:*central-registry*)' \
     --eval '(ql:quickload :photo-ai-lisp :silent t)' \
     --eval '(asdf:load-system :photo-ai-lisp/tests)' \
     --eval '(fiveam:run! (find-symbol "PHOTO-AI-LISP-TESTS" "PHOTO-AI-LISP/TESTS"))'
