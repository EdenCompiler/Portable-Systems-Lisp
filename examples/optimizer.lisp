(ffi:import-function "side_effect_c" ((value u64)) -> u64)

(defun increment (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (wrap+ value 1))

(defun call_increment (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (increment value))

(defun constant_wrap ()
  (declare (returns u8) (c-export :c))
  (wrap+ 250 10))

(defun signed_wrap ()
  (declare (returns s8) (c-export :c))
  (wrap+ -120 -20))

(defun signed_less (left right)
  (declare (type s8 left right) (returns u64) (c-export :c))
  (if (< left right) 1 0))

(defun discard_pure (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (progn (wrap+ value 1) value))

(defun effect_probe (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (progn
    (ffi:call side_effect_c value)
    (if (< value 10)
        (wrap+ value 32)
        (wrap+ value 2))))

(defun volatile_discard (status)
  (declare (type (ptr u8 :volatile) status)
           (returns u8) (c-export :c))
  (progn (deref status) 42))
