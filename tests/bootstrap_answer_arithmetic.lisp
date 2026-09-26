(defun answer ()
  (declare (returns u64) (c-export :c))
  (wrap+ (wrap* 6 7) (wrap- 10 10)))
