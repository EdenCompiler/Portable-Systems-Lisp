(defun broken (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (wrap+ value (unknown value)))
