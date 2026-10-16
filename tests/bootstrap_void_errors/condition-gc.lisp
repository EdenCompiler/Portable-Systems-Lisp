(defun bad ()
  (declare (returns u64))
  (if (collect-garbage) 42 0))
