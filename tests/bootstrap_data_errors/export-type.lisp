(ffi:export-data "counter" void 0)

(defun answer ()
  (declare (returns u64) (c-export :c))
  42)
