(ffi:source "ffi_math.c")
(ffi:import-function "scale_c" ((value u64) (factor u64)) -> u64)

(defun scale_then_add (value)
  (declare (type u64 value)
           (returns u64)
           (c-export :c))
  (wrap+ (ffi:call scale_c value 2) 2))
