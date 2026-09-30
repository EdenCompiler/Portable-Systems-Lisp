(ffi:export-data "counter" u64 0)

(defun counter ()
  (declare (returns u64) (c-export :c))
  42)
