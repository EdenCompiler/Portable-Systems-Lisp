(defun answer ()
  (declare (returns u64) (c-export :c))
  (ffi:call missing 42))
