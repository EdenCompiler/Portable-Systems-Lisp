(defun masked_shift (value count)
  (declare (type u64 value count) (returns u64) (c-export :c))
  (bits-and (shr64 value count) 255))

(defun answer ()
  (declare (returns u64) (c-export :c))
  (masked_shift #x2a00 8))
