(ffi:import-function "side_effect" () -> void)
(defun bad ()
  (declare (returns u64))
  (let ((done (ffi:call side_effect))) (if done 42 0)))
