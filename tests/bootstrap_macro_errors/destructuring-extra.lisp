(defmacro bad_nested_extra (()) 1)
(defun bad_nested_extra ()
  (declare (returns u64) (c-export :c))
  (bad_nested_extra (1)))
