(ffi:import-function "psl_rt_value_handle_open" () -> usize)
(defun bad_handle_open ()
  (declare (returns usize))
  (without-allocation (ffi:call psl_rt_value_handle_open)))
