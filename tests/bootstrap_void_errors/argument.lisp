(ffi:import-function "side_effect" () -> void)
(ffi:import-function "consume" ((input u64)) -> void)
(defun bad () (declare (returns void)) (ffi:call consume (ffi:call side_effect)))
