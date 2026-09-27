(ffi:import-function "helper" ((input u64)) -> u64)
(defun answer ()
  (declare (returns u64) (c-export :c))
  (ffi:call helper))
