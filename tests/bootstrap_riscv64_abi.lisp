(ffi:import-function "check_u32_register" ((value u32)) -> u32)
(ffi:import-function "check_u32_stack"
  ((a u64) (b u64) (c u64) (d u64) (e u64) (f u64) (g u64) (h u64)
   (value u32)) -> u32)

(defun rv_u32_result ()
  (declare (returns u32) (c-export :c))
  #x80000000)

(defun rv_u32_input (value)
  (declare (type u32 value) (returns u64) (c-export :c))
  (wrap-cast u64 value))

(defun rv_check_register ()
  (declare (returns u64) (c-export :c))
  (wrap-cast u64 (ffi:call check_u32_register #xffffffff)))

(defun rv_check_stack ()
  (declare (returns u64) (c-export :c))
  (wrap-cast u64 (ffi:call check_u32_stack 1 2 3 4 5 6 7 8 #xffffffff)))

(defun rv_unaligned_roundtrip (pointer)
  (declare (type (ptr u8) pointer) (returns u64) (c-export :c))
  (let ((word (ptr-cast (ptr u64) (pointer+ pointer 1))))
    (store word #xfedcba9876543210)
    (deref word)))
