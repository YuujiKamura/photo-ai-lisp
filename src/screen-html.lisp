(in-package #:photo-ai-lisp)

(defparameter *ansi-color-palette*
  #("#000000" "#cd0000" "#00cd00" "#cdcd00"
    "#0000ee" "#cd00cd" "#00cdcd" "#e5e5e5"
    "#7f7f7f" "#ff0000" "#00ff00" "#ffff00"
    "#5c5cff" "#ff00ff" "#00ffff" "#ffffff"))

(defun %palette-component (index)
  (svref #(0 95 135 175 215 255) index))

(defun %xterm-color->hex (index)
  (cond
    ((<= 0 index 15)
     (svref *ansi-color-palette* index))
    ((<= 16 index 231)
     (let* ((offset (- index 16))
            (r (%palette-component (floor offset 36)))
            (g (%palette-component (floor (mod offset 36) 6)))
            (b (%palette-component (mod offset 6))))
       (format nil "#~2,'0X~2,'0X~2,'0X" r g b)))
    ((<= 232 index 255)
     (let ((shade (+ 8 (* 10 (- index 232)))))
       (format nil "#~2,'0X~2,'0X~2,'0X" shade shade shade)))
    (t
     (svref *ansi-color-palette* 7))))

(defun %cell-attrs-equal (left right)
  (and (= (cell-fg left) (cell-fg right))
       (= (cell-bg left) (cell-bg right))
       (eql (cell-bold left) (cell-bold right))
       (eql (cell-underline left) (cell-underline right))
       (eql (cell-reverse left) (cell-reverse right))))

(defun %effective-colors (cell)
  (if (cell-reverse cell)
      (values (cell-bg cell) (cell-fg cell))
      (values (cell-fg cell) (cell-bg cell))))

(defun %cell-style (cell)
  (multiple-value-bind (fg bg) (%effective-colors cell)
    (with-output-to-string (out)
      (format out "color:~A;background:~A"
              (%xterm-color->hex fg)
              (%xterm-color->hex bg))
      (when (cell-bold cell)
        (write-string ";font-weight:bold" out))
      (when (cell-underline cell)
        (write-string ";text-decoration:underline" out)))))

(defun %emit-span-run (out text attrs)
  (format out "<span style=\"~A\">~A</span>"
          (%cell-style attrs)
          (cl-who:escape-string-minimal text)))

(defun screen->html (screen)
  (with-output-to-string (out)
    (write-string "<pre class=\"screen\">" out)
    (dotimes (row (screen-rows screen))
      (let* ((first-cell (aref (screen-buffer screen) row 0))
             (run-attrs first-cell)
             (run-chars (make-array 0 :element-type 'character :adjustable t :fill-pointer 0)))
        (dotimes (col (screen-cols screen))
          (let ((cell (aref (screen-buffer screen) row col)))
            (if (%cell-attrs-equal cell run-attrs)
                (vector-push-extend (cell-char cell) run-chars)
                (progn
                  (%emit-span-run out (coerce run-chars 'string) run-attrs)
                  (setf run-attrs cell
                        run-chars (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
                  (vector-push-extend (cell-char cell) run-chars)))))
        (%emit-span-run out (coerce run-chars 'string) run-attrs))
      (when (< row (1- (screen-rows screen)))
        (terpri out)))
    (write-string "</pre>" out)))
