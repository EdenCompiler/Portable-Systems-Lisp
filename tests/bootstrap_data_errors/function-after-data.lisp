(ffi:import-data "counter" u64)

(defun counter ()
  (declare (returns u64) (c-export :c))
  42)
