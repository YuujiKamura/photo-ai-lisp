(in-package #:photo-ai-lisp)

;;; ANSI / ECMA-48 Parser
;;;
;;; Implementation of a state machine for parsing ANSI escape sequences.
;;; Supported sequences:
;;; - Printable characters (0x20-0x7E, 0xA0-0xFF)
;;; - CSI sequences (Cursor move, Position, Erase, SGR)
;;; - OSC sequences (Title)
;;; - Basic control characters (BEL, BS, HT, LF, CR)

(defclass ansi-parser ()
  ((state :initform :ground :accessor parser-state)
   (params :initform nil :accessor parser-params)
   (current-param :initform nil :accessor parser-current-param)
   (osc-buffer :initform (make-array 0 :element-type 'character :adjustable t :fill-pointer 0) :accessor parser-osc-buffer)
   (collected-bytes :initform (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0) :accessor parser-collected-bytes))
  (:documentation "State machine for parsing ANSI/VT100 escape sequences."))

(defun make-parser ()
  "Create a new ANSI parser state object."
  (make-instance 'ansi-parser))

(defun reset-parser-sequence (parser)
  "Reset the current sequence being parsed."
  (with-slots (params current-param collected-bytes) parser
    (setf params nil
          current-param nil)
    (setf (fill-pointer collected-bytes) 0)))

(defun handle-csi-final (parser byte events)
  "Process the final byte of a CSI sequence."
  (with-slots (state params current-param collected-bytes) parser
    (when current-param (push current-param params))
    (let* ((final-params (nreverse params))
           (final-char (code-char byte))
           (p1 (let ((p (first final-params))) (if (or (not p) (= p 0)) 1 p)))
           (p2 (let ((p (second final-params))) (if (or (not p) (= p 0)) 1 p))))
      (case final-char
        (#\A (push `(:type :cursor-move :direction :up :count ,p1) events))
        (#\B (push `(:type :cursor-move :direction :down :count ,p1) events))
        (#\C (push `(:type :cursor-move :direction :right :count ,p1) events))
        (#\D (push `(:type :cursor-move :direction :left :count ,p1) events))
        (#\H (push `(:type :cursor-position :row ,p1 :col ,p2) events))
        (#\J (push `(:type :erase-display :mode ,(or (first final-params) 0)) events))
        (#\K (push `(:type :erase-line :mode ,(or (first final-params) 0)) events))
        (#\m (push `(:type :set-attr :attrs ,(or final-params '(0))) events))
        (t (push `(:type :unknown :raw ,(copy-seq collected-bytes)) events))))
    (setf state :ground)
    (setf (fill-pointer collected-bytes) 0)
    events))

(defun handle-osc-done (parser events)
  "Process a completed OSC sequence."
  (with-slots (osc-buffer collected-bytes) parser
    (let* ((str (coerce osc-buffer 'string))
           (semi (position #\; str)))
      (if semi
          (let ((cmd (subseq str 0 semi))
                (val (subseq str (1+ semi))))
            (if (member cmd '("0" "1" "2") :test #'string=)
                (push `(:type :set-title :title ,val) events)
                (push `(:type :unknown :raw ,(copy-seq collected-bytes)) events)))
          (push `(:type :unknown :raw ,(copy-seq collected-bytes)) events)))
    (setf (fill-pointer collected-bytes) 0)
    events))

(defun parser-feed (parser byte)
  "Feed one byte into the parser. Returns a list of events generated."
  (let ((events nil))
    (with-slots (state params current-param osc-buffer collected-bytes) parser
      (vector-push-extend byte collected-bytes)
      (case state
        (:ground
         (cond
           ((= byte #x1b) (setf state :escape))
           ((or (<= #x20 byte #x7e) (>= byte #xa0))
            (push `(:type :print :char ,(code-char byte)) events)
            (setf (fill-pointer collected-bytes) 0))
           ((= byte #x07) (push `(:type :bell) events) (setf (fill-pointer collected-bytes) 0))
           ((= byte #x08) (push `(:type :bs) events) (setf (fill-pointer collected-bytes) 0))
           ((= byte #x09) (push `(:type :ht) events) (setf (fill-pointer collected-bytes) 0))
           ((= byte #x0a) (push `(:type :lf) events) (setf (fill-pointer collected-bytes) 0))
           ((= byte #x0d) (push `(:type :cr) events) (setf (fill-pointer collected-bytes) 0))
           (t (push `(:type :unknown :raw ,(copy-seq collected-bytes)) events)
              (setf (fill-pointer collected-bytes) 0))))
        (:escape
         (case (code-char byte)
           (#\[ (setf state :csi-entry
                      params nil
                      current-param nil))
           (#\] (setf state :osc-string
                      (fill-pointer osc-buffer) 0))
           (t (push `(:type :unknown :raw ,(copy-seq collected-bytes)) events)
              (setf state :ground
                    (fill-pointer collected-bytes) 0))))
        (:csi-entry
         (cond
           ((<= #x30 byte #x39) ;; 0-9
            (setf state :csi-param
                  current-param (- byte #x30)))
           ((= byte #x3b) ;; ;
            (push 0 params)
            (setf state :csi-param
                  current-param nil))
           (t (setf events (handle-csi-final parser byte events)))))
        (:csi-param
         (cond
           ((<= #x30 byte #x39) ;; 0-9
            (setf current-param (+ (* (or current-param 0) 10) (- byte #x30))))
           ((= byte #x3b) ;; ;
            (push (or current-param 0) params)
            (setf current-param nil))
           (t (setf events (handle-csi-final parser byte events)))))
        (:osc-string
         (cond
           ((= byte #x07) ;; BEL
            (setf events (handle-osc-done parser events))
            (setf state :ground))
           ((= byte #x1b) ;; ESC (potential ST)
            (setf state :osc-esc))
           (t (vector-push-extend (code-char byte) osc-buffer))))
        (:osc-esc
         (case (code-char byte)
           (#\\ ;; ST
            (setf events (handle-osc-done parser events))
            (setf state :ground))
           (t ;; Not an ST, back to OSC string or fail?
            ;; ANSI says ESC followed by anything other than \ is weird.
            ;; We'll just push the ESC and the byte back to buffer and continue.
            (vector-push-extend #\Esc osc-buffer)
            (vector-push-extend (code-char byte) osc-buffer)
            (setf state :osc-string))))))
    (nreverse events)))

(defun parser-feed-string (parser s)
  "Feed a string into the parser by converting it to bytes (ASCII/Latin1).
Note: This doesn't handle UTF-8 encoding yet, it feeds characters as-is."
  (let ((all-events nil))
    (loop for c across s
          for byte = (char-code c)
          do (setf all-events (nconc all-events (parser-feed parser byte))))
    all-events))
