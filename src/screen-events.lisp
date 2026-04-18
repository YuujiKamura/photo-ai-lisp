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
