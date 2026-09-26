(defun answer ()
  (declare (returns u64) (c-export :c))
  (progn (let ((x 42)) x) x))
