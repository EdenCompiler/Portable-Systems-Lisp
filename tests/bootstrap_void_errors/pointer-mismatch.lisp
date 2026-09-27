(ffi:import-function "free" ((memory (ptr void))) -> void)
(defun bad (memory) (declare (type (ptr u64) memory) (returns void)) (ffi:call free memory))
