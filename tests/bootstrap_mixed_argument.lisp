(defun signed_value (value)
  (declare (type s8 value) (returns s8))
  value)

(defun invalid_argument (value)
  (declare (type u8 value) (returns s8) (c-export :c))
  (signed_value value))
