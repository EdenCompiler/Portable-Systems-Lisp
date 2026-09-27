(ffi:import-function "helper" ((input u64)) -> u64)
(defun helper (input)
  (declare (type u64 input) (returns u64) (c-export :c))
  input)
