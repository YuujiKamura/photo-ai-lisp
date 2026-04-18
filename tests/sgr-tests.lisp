(in-package #:photo-ai-lisp/tests)

(def-suite sgr-tests
  :in photo-ai-lisp-tests
  :description "5e.4a — pure SGR parameter parser")

(in-suite sgr-tests)

;;; Helper: assert that KEY appears in PLIST with VALUE.
(defun %sgr-has (plist key value)
  (loop for (k v) on plist by #'cddr
        when (eq k key)
          do (return (equal v value)))
  nil)

;;; ---- reset ----------------------------------------------------------------

(test sgr-nil-is-implicit-reset
  "nil input → (:reset t) per ECMA-48 §8.3.117"
  (let ((r (photo-ai-lisp:parse-sgr-params nil)))
    (is (equal '(:reset t) r)
        "nil should produce (:reset t), got ~s" r)))

(test sgr-empty-list-is-implicit-reset
  (let ((r (photo-ai-lisp:parse-sgr-params '())))
    (is (equal '(:reset t) r)
        "empty list should produce (:reset t), got ~s" r)))

(test sgr-explicit-reset
  (let ((r (photo-ai-lisp:parse-sgr-params '(0))))
    (is (equal '(:reset t) r)
        "param 0 should produce (:reset t), got ~s" r)))

;;; ---- text style on --------------------------------------------------------

(test sgr-bold-on
  (is (equal '(:bold t) (photo-ai-lisp:parse-sgr-params '(1)))))

(test sgr-faint-on
  (is (equal '(:faint t) (photo-ai-lisp:parse-sgr-params '(2)))))

(test sgr-italic-on
  (is (equal '(:italic t) (photo-ai-lisp:parse-sgr-params '(3)))))

(test sgr-underline-on
  (is (equal '(:underline t) (photo-ai-lisp:parse-sgr-params '(4)))))

(test sgr-reverse-on
  (is (equal '(:reverse t) (photo-ai-lisp:parse-sgr-params '(7)))))

;;; ---- text style off -------------------------------------------------------

(test sgr-bold-off
  (is (equal '(:bold :reset) (photo-ai-lisp:parse-sgr-params '(22)))))

(test sgr-italic-off
  (is (equal '(:italic :reset) (photo-ai-lisp:parse-sgr-params '(23)))))

(test sgr-underline-off
  (is (equal '(:underline :reset) (photo-ai-lisp:parse-sgr-params '(24)))))

(test sgr-reverse-off
  (is (equal '(:reverse :reset) (photo-ai-lisp:parse-sgr-params '(27)))))

;;; ---- standard fg (30-37) --------------------------------------------------

(test sgr-fg-black
  (is (equal '(:fg 0) (photo-ai-lisp:parse-sgr-params '(30)))))

(test sgr-fg-red
  (is (equal '(:fg 1) (photo-ai-lisp:parse-sgr-params '(31)))))

(test sgr-fg-white
  (is (equal '(:fg 7) (photo-ai-lisp:parse-sgr-params '(37)))))

(test sgr-fg-default
  (is (equal '(:fg :default) (photo-ai-lisp:parse-sgr-params '(39)))))

;;; ---- standard bg (40-47) --------------------------------------------------

(test sgr-bg-black
  (is (equal '(:bg 0) (photo-ai-lisp:parse-sgr-params '(40)))))

(test sgr-bg-green
  (is (equal '(:bg 2) (photo-ai-lisp:parse-sgr-params '(42)))))

(test sgr-bg-white
  (is (equal '(:bg 7) (photo-ai-lisp:parse-sgr-params '(47)))))

(test sgr-bg-default
  (is (equal '(:bg :default) (photo-ai-lisp:parse-sgr-params '(49)))))

;;; ---- bright fg (90-97) ----------------------------------------------------

(test sgr-bright-fg-red
  "param 91 → (:fg 1 :bright t)"
  (is (equal '(:fg 1 :bright t) (photo-ai-lisp:parse-sgr-params '(91)))))

(test sgr-bright-fg-cyan
  "param 96 → (:fg 6 :bright t)"
  (is (equal '(:fg 6 :bright t) (photo-ai-lisp:parse-sgr-params '(96)))))

;;; ---- bright bg (100-107) --------------------------------------------------

(test sgr-bright-bg-blue
  "param 104 → (:bg 4 :bright t)"
  (is (equal '(:bg 4 :bright t) (photo-ai-lisp:parse-sgr-params '(104)))))

(test sgr-bright-bg-white
  "param 107 → (:bg 7 :bright t)"
  (is (equal '(:bg 7 :bright t) (photo-ai-lisp:parse-sgr-params '(107)))))

;;; ---- 256-colour (38;5;N and 48;5;N) ----------------------------------------

(test sgr-256-fg
  "38;5;200 → (:fg 200)"
  (is (equal '(:fg 200) (photo-ai-lisp:parse-sgr-params '(38 5 200)))))

(test sgr-256-fg-low
  "38;5;9 → (:fg 9) — standard range via 256-colour path"
  (is (equal '(:fg 9) (photo-ai-lisp:parse-sgr-params '(38 5 9)))))

(test sgr-256-bg
  "48;5;50 → (:bg 50)"
  (is (equal '(:bg 50) (photo-ai-lisp:parse-sgr-params '(48 5 50)))))

;;; ---- combined sequences ---------------------------------------------------

(test sgr-reset-bold-fg
  "0;1;31 → (:reset t :bold t :fg 1)"
  (is (equal '(:reset t :bold t :fg 1)
             (photo-ai-lisp:parse-sgr-params '(0 1 31)))))

(test sgr-bold-then-bold-off
  "1;22 → (:bold t :bold :reset) — both mutations preserved in order"
  (is (equal '(:bold t :bold :reset)
             (photo-ai-lisp:parse-sgr-params '(1 22)))))

(test sgr-fg-then-fg
  "31;32 → (:fg 1 :fg 2) — last fg wins when consumer applies"
  (is (equal '(:fg 1 :fg 2)
             (photo-ai-lisp:parse-sgr-params '(31 32)))))

(test sgr-full-style
  "1;4;7;31;42 → bold+underline+reverse+fg1+bg2"
  (let ((r (photo-ai-lisp:parse-sgr-params '(1 4 7 31 42))))
    (is (equal r '(:bold t :underline t :reverse t :fg 1 :bg 2))
        "combined SGR, got ~s" r)))

;;; ---- edge cases -----------------------------------------------------------

(test sgr-unknown-param-skipped
  "Unsupported param produces empty plist (no crash)."
  (is (null (photo-ai-lisp:parse-sgr-params '(99)))
      "unknown param 99 should be silently skipped"))

(test sgr-38-truncated
  "38 without 5;N should be silently skipped."
  (is (null (photo-ai-lisp:parse-sgr-params '(38)))
      "bare 38 should produce nil"))

(test sgr-38-5-truncated
  "38;5 without N should be silently skipped."
  (is (null (photo-ai-lisp:parse-sgr-params '(38 5)))
      "38;5 without N should produce nil"))

(test sgr-preserves-subsequent-params-after-unknown
  "Unknown param does not consume following valid params."
  (is (equal '(:bold t)
             (photo-ai-lisp:parse-sgr-params '(99 1)))
      "bold after unknown param should still parse"))
