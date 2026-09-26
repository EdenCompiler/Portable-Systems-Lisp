(defun answer ()
  (declare (returns u64) (c-export :c))
  (wrap- (wrap+ #xffffffffffffffff 45) 2))
