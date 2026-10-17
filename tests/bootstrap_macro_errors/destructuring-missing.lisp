(defmacro bad_nested_missing ((left right)) left)
(defun bad_nested_missing ()
  (declare (returns u64) (c-export :c))
  (bad_nested_missing (1)))
