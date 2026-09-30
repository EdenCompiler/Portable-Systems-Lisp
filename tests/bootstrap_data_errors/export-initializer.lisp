(ffi:export-data "counter" u64 missing)

(defun answer ()
  (declare (returns u64) (c-export :c))
  42)
