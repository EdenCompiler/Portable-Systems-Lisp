(defun unknown-address ()
  (declare (returns (ptr u64)) (c-export :c))
  (ffi:address-of missing_counter))
