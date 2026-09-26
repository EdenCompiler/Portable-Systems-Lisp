(defcstruct pair (value u8))
(defun bad (p) (declare (type (ptr pair) p) (returns (ptr u8))) (field-pointer p value))
