(ffi:import-function "side_effect" () -> void)
(defun bad () (declare (returns u64)) (if (ffi:call side_effect) 42 0))
