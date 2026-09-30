(defcstruct |bad-layout| (field u64))
(defun broken ()
  (declare (returns u64))
  (sizeof '|bad-layout|))
