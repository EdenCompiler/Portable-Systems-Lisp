(ffi:source "include_helper.c")
(ffi:import-function "include_helper" ((value u64)) -> u64)

(defun included_call (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (ffi:call include_helper value))
