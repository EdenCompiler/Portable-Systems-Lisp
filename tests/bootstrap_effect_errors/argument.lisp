(ffi:import-function "unknown" () -> u64)
(ffi:import-function "safe" ((x u64)) -> u64 :no-allocation)
(defun bad () (declare (returns u64)) (without-allocation (ffi:call safe (ffi:call unknown))))
