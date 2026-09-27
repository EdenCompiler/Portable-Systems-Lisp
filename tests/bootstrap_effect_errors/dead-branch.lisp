(ffi:import-function "unknown" () -> u64)
(defun bad () (declare (returns u64)) (without-allocation (if nil (ffi:call unknown) 42)))
