(defpackage #:photo-ai-lisp
  (:use #:cl #:hunchentoot #:cl-who)
  (:shadow #:start #:stop)
  (:export #:start #:stop
           ;; ansi parser
           #:make-parser
           #:parser-feed
           #:parser-feed-string
           ;; cell (5a)
           #:make-cell #:copy-cell
           #:cell-char #:cell-fg #:cell-bg
           #:cell-bold #:cell-underline #:cell-reverse
           ;; screen grid (5b)
           #:make-screen
           #:screen-rows #:screen-cols #:screen-buffer #:screen-cursor
           ;; cursor model (5c)
           #:make-cursor
           #:cursor-row #:cursor-col #:cursor-visible #:cursor-attrs
           #:cursor-move
           ;; scrollback (5d)
           #:screen-scrollback #:screen-scroll-up
           ;; event dispatch (5e.1)
           #:apply-event #:register-event-handler
           ;; screen snapshot (5f)
           #:screen->text
           #:screen->html
           ;; sgr parser (5e.4a)
           #:parse-sgr-params))
