(ffi:import-function "consume_c" ((value (ptr void))) -> void)

(defun relay_void (value)
  (declare (type (ptr void) value)
           (returns void)
           (c-export :c))
  (ffi:call consume_c value))

(defun notify_then_42 (value)
  (declare (type (ptr void) value)
           (returns c-int)
           (c-export :c))
  (ffi:call consume_c value)
  42)
