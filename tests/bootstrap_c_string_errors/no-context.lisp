(defun answer ()
  (declare (returns u64) (c-export :c))
  (ffi:c-string "wrong result"))
