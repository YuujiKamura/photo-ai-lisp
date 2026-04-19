#!/bin/bash
export PATH="/c/Users/yuuji/SBCLLocal/PFiles/Steel Bank Common Lisp:$PATH"
sbcl --non-interactive \
     --load ~/quicklisp/setup.lisp \
     --eval '(push (uiop:getcwd) asdf:*central-registry*)' \
     --eval '(ql:quickload :photo-ai-lisp :silent t)' \
     --eval '(asdf:load-system :photo-ai-lisp/tests)' \
     --eval '(fiveam:run! (find-symbol "CP-PROTOCOL-MAKE-INPUT" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-PROTOCOL-MAKE-TAIL" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-PROTOCOL-MAKE-STATE" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-PROTOCOL-MAKE-LIST-TABS" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-PROTOCOL-PARSE-RESPONSE" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-CLIENT-CONNECT-RETURNS-OBJECT" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-CLIENT-SEND-COMMAND-SYNC" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-CLIENT-TAIL-HELPER" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "CP-CLIENT-INPUT-HELPER" "PHOTO-AI-LISP/TESTS"))' \
     --eval '(fiveam:run! (find-symbol "PIPELINE-INVOKE-VIA-CP-RETURNS-VALUES" "PHOTO-AI-LISP/TESTS"))'
