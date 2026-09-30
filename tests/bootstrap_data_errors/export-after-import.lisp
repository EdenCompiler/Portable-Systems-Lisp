(ffi:import-data "counter" u64)
(ffi:export-data "counter" u64 0)

(defun answer ()
  (declare (returns u64) (c-export :c))
  42)
