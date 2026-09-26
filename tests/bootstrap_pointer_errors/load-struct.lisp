(defcstruct pair (value u8))
(defun bad (p) (declare (type (ptr pair) p) (returns u8)) (deref p))
