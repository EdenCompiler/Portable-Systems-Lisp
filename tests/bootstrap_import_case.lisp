(ffi:import-function "MixedCaseAdd" ((value u64)) -> u64 :no-allocation)

(defun call_mixed_case (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (ffi:call "MixedCaseAdd" value))
