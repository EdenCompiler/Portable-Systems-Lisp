(defun counter ()
  (declare (returns u64) (c-export :c))
  42)

(ffi:import-data "counter" u64)
