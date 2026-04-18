(in-package #:photo-ai-lisp)

(defun %clamp (value lower upper)
  (min upper (max lower value)))

(defun %set-cursor-position (screen row col)
  (let ((cursor (screen-cursor screen)))
    (setf (cursor-row cursor)
          (%clamp row 0 (1- (screen-rows screen)))
          (cursor-col cursor)
          (%clamp col 0 (1- (screen-cols screen))))))

(defun %reset-cell-at (screen row col)
  (setf (aref (screen-buffer screen) row col) (make-cell)))

(defun %erase-range (screen start-row start-col end-row end-col)
  (loop for row from start-row to end-row
        do (loop for col from (if (= row start-row) start-col 0)
                 to (if (= row end-row) end-col (1- (screen-cols screen)))
                 do (%reset-cell-at screen row col))))

(defun %default-fg () 7)

(defun %default-bg () 0)

(defun %apply-sgr-changes (cell changes)
  (loop while changes
        for key = (pop changes)
        for value = (pop changes)
        do (case key
             (:reset
              (setf cell (make-cell)))
             (:bold
              (setf (cell-bold cell) (eq value t)))
             (:underline
              (setf (cell-underline cell) (eq value t)))
             (:reverse
              (setf (cell-reverse cell) (eq value t)))
             (:fg
              (let* ((bright (and changes
                                  (eq (first changes) :bright)
                                  (eq (second changes) t)))
                     (fg (cond
                           ((eq value :default) (%default-fg))
                           ((and bright (integerp value)) (+ 8 value))
                           (t value))))
                (setf (cell-fg cell) fg)
                (when bright
                  (pop changes)
                  (pop changes))))
             (:bg
              (let* ((bright (and changes
                                  (eq (first changes) :bright)
                                  (eq (second changes) t)))
                     (bg (cond
                           ((eq value :default) (%default-bg))
                           ((and bright (integerp value)) (+ 8 value))
                           (t value))))
                (setf (cell-bg cell) bg)
                (when bright
                  (pop changes)
                  (pop changes))))
             (:bright nil)))
  cell)

(register-event-handler
 :cursor-move
 (lambda (screen event)
   (let* ((cursor (screen-cursor screen))
          (count (or (getf event :count) 1))
          (row (cursor-row cursor))
          (col (cursor-col cursor)))
     (ecase (getf event :direction)
       (:up (decf row count))
       (:down (incf row count))
       (:right (incf col count))
       (:left (decf col count)))
     (%set-cursor-position screen row col))))

(register-event-handler
 :cursor-position
 (lambda (screen event)
   (%set-cursor-position screen
                         (1- (or (getf event :row) 1))
                         (1- (or (getf event :col) 1)))))

(register-event-handler
 :erase-display
 (lambda (screen event)
   (let* ((cursor (screen-cursor screen))
          (row (cursor-row cursor))
          (col (cursor-col cursor)))
     (case (getf event :mode)
       (0 (%erase-range screen row col
                        (1- (screen-rows screen))
                        (1- (screen-cols screen))))
       (1 (%erase-range screen 0 0 row col))
       (2 (%erase-range screen 0 0
                        (1- (screen-rows screen))
                        (1- (screen-cols screen))))))))

(register-event-handler
 :erase-line
 (lambda (screen event)
   (let* ((cursor (screen-cursor screen))
          (row (cursor-row cursor))
          (col (cursor-col cursor)))
     (case (getf event :mode)
       (0 (%erase-range screen row col row (1- (screen-cols screen))))
       (1 (%erase-range screen row 0 row col))
       (2 (%erase-range screen row 0 row (1- (screen-cols screen))))))))

(register-event-handler
 :set-attr
 (lambda (screen event)
   (let* ((cursor (screen-cursor screen))
          (changes (parse-sgr-params (getf event :attrs))))
     (setf (cursor-attrs cursor)
           (%apply-sgr-changes (copy-cell (cursor-attrs cursor)) changes)))))
