(ffi:import-function "unknown" () -> u64)
(defun bad () (declare (returns u64)) (without-allocation (middle)))
(defun middle () (declare (returns u64)) (leaf))
(defun leaf () (declare (returns u64)) (ffi:call unknown))
