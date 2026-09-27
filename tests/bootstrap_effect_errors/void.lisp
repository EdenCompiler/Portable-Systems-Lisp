(ffi:import-function "unknown" () -> void)
(defun bad () (declare (returns void)) (without-allocation (ffi:call unknown)))
