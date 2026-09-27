(ffi:import-function "side_effect" () -> void)
(defun bad () (declare (returns u64)) (ffi:call side_effect))
