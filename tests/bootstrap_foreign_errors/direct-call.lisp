(ffi:import-function "foreign_c" ((input u64)) -> u64)
(defun answer ()
  (declare (returns u64) (c-export :c))
  (foreign_c 42))
