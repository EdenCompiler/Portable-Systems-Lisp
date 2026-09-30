(ffi:export-data "counter" (ptr u8) 1)

(defun answer ()
  (declare (returns u64) (c-export :c))
  42)
