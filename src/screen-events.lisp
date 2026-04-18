(in-package #:photo-ai-lisp)

(defun %clamp (value lower upper)
  (min upper (max lower value)))

(defun %set-cursor-position (screen row col)
  (let ((cursor (screen-cursor screen)))
    (setf (cursor-row cursor)
          (%clamp row 0 (1- (screen-rows screen)))
          (cursor-col cursor)
          (%clamp col 0 (1- (screen-cols screen))))))

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
