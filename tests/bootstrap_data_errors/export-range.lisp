(ffi:export-data "counter" u8 256)

(defun answer ()
  (declare (returns u64) (c-export :c))
  42)
