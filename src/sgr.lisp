(in-package #:photo-ai-lisp)

;;; 5e.4a — Pure SGR (Select Graphic Rendition) parameter parser.
;;;
;;; (parse-sgr-params params) takes a list of integer SGR parameter values
;;; (the numbers between \e[ and m) and returns a property list describing
;;; the attribute mutations they represent, in left-to-right order.
;;;
;;; Key/value conventions:
;;;   :reset     t          — reset all attributes
;;;   :bold      t/:reset   — bold on / off
;;;   :faint     t/:reset   — faint/dim on / off
;;;   :italic    t/:reset   — italic on / off
;;;   :underline t/:reset   — underline on / off
;;;   :reverse   t/:reset   — reverse video on / off
;;;   :conceal   t/:reset   — concealed on / off
;;;   :fg        0-7        — standard foreground colour (0=black … 7=white)
;;;   :fg        8-255      — extended / 256-colour foreground
;;;   :fg        :default   — restore default foreground
;;;   :bg        0-7        — standard background colour
;;;   :bg        8-255      — extended / 256-colour background
;;;   :bg        :default   — restore default background
;;;   :bright    t          — emitted alongside :fg/:bg for params 90-107
;;;
;;; Consecutive params that address the same key are both emitted; the
;;; consumer (5e.4b) applies them left-to-right so the last one wins.
;;;
;;; Unknown/unsupported params are silently skipped.

(defun parse-sgr-params (params)
  "Parse a list of SGR integer parameters into a flat property list.
Empty or nil input is treated as a single implicit 0 (reset) per ECMA-48."
  (let ((remaining (if (null params) '(0) (copy-list params)))
        (result '()))
    (flet ((emit (&rest kvs)
             (setf result (nconc result (copy-list kvs)))))
      (loop while remaining
            for p = (pop remaining)
            do (cond
                 ;; --- Reset ---
                 ((= p 0)  (emit :reset t))

                 ;; --- Text style on ---
                 ((= p 1)  (emit :bold t))
                 ((= p 2)  (emit :faint t))
                 ((= p 3)  (emit :italic t))
                 ((= p 4)  (emit :underline t))
                 ((= p 7)  (emit :reverse t))
                 ((= p 8)  (emit :conceal t))

                 ;; --- Text style off ---
                 ((= p 22) (emit :bold :reset))
                 ((= p 23) (emit :italic :reset))
                 ((= p 24) (emit :underline :reset))
                 ((= p 27) (emit :reverse :reset))
                 ((= p 28) (emit :conceal :reset))

                 ;; --- Standard fg colours 30-37 ---
                 ((and (>= p 30) (<= p 37))
                  (emit :fg (- p 30)))

                 ;; --- Extended fg colour ---
                 ((= p 38)
                  (cond
                    ;; 38;5;N  → 256-colour fg
                    ((and remaining
                          (= (first remaining) 5)
                          (rest remaining))
                     (pop remaining)
                     (emit :fg (pop remaining)))
                    ;; 38;2;R;G;B → true-colour fg (skip, not yet rendered)
                    ((and remaining
                          (= (first remaining) 2)
                          (>= (length remaining) 4))
                     (pop remaining)           ; 2
                     (pop remaining)           ; R
                     (pop remaining)           ; G
                     (pop remaining))          ; B — silently dropped
                    ;; Malformed / unsupported — skip
                    (t nil)))

                 ;; --- Default fg ---
                 ((= p 39) (emit :fg :default))

                 ;; --- Standard bg colours 40-47 ---
                 ((and (>= p 40) (<= p 47))
                  (emit :bg (- p 40)))

                 ;; --- Extended bg colour ---
                 ((= p 48)
                  (cond
                    ;; 48;5;N  → 256-colour bg
                    ((and remaining
                          (= (first remaining) 5)
                          (rest remaining))
                     (pop remaining)
                     (emit :bg (pop remaining)))
                    ;; 48;2;R;G;B → true-colour bg (skip)
                    ((and remaining
                          (= (first remaining) 2)
                          (>= (length remaining) 4))
                     (pop remaining) (pop remaining)
                     (pop remaining) (pop remaining))
                    (t nil)))

                 ;; --- Default bg ---
                 ((= p 49) (emit :bg :default))

                 ;; --- Bright fg (high intensity) 90-97 ---
                 ;; Encoded as standard colour index 0-7 + :bright t marker.
                 ((and (>= p 90) (<= p 97))
                  (emit :fg (- p 90) :bright t))

                 ;; --- Bright bg (high intensity) 100-107 ---
                 ((and (>= p 100) (<= p 107))
                  (emit :bg (- p 100) :bright t))

                 ;; --- Unknown param: skip silently ---
                 (t nil))))
    result))
