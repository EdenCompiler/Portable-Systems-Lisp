(defun increment-size (value)
  (declare (type usize value) (returns usize))
  (wrap+ value 1))

(defun add_size (left right)
  (declare (type usize left right)
           (returns usize)
           (c-export :c))
  (wrap+ left right))

(defun choose_size (left right)
  (declare (type usize left right)
           (returns usize)
           (c-export :c))
  (if (< left right) right left))

(defun answer_size ()
  (declare (returns usize) (c-export :c))
  (add_size (increment-size 40) 1))
