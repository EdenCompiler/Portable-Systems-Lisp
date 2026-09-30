(defcstruct box (|bad-field| u64))
(defun broken ()
  (declare (returns u64))
  (sizeof 'box))
