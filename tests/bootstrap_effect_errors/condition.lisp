(ffi:import-function "unknown" () -> u64)
(defun bad () (declare (returns u64)) (without-allocation (if (ffi:call unknown) 42 0)))
