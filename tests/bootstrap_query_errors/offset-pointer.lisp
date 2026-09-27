(defcstruct item (word u64))
(defun bad () (declare (returns usize)) (offset-of '(ptr item) 'word))
