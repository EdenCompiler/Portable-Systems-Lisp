(ffi:import-function "side_effect" () -> void)
(defun bad () (declare (returns void)) (if t (ffi:call side_effect) 42))
