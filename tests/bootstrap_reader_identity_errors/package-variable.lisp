(defun identity_rejected (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  ffi::value)
