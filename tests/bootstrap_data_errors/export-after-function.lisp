(defun counter ()
  (declare (returns u64) (c-export :c))
  42)

(ffi:export-data "counter" u64 0)
