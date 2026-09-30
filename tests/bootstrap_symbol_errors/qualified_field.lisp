(defcstruct box (OTHER:BAD-FIELD u64))
(defun broken ()
  (declare (returns u64))
  1)
