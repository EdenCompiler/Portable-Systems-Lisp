(defun broken (value)
  (declare (type u64 value) (returns u64))
  (OTHER:WRAP+ value 1))
