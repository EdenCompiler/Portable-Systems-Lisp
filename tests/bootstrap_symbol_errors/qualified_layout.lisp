(defcstruct OTHER:BAD-LAYOUT (field u64))
(defun broken ()
  (declare (returns u64))
  1)
