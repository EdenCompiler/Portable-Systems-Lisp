(defcstruct packet (tag u8))
(defstruct/packed packet (tag u8))
(defun answer () (declare (returns u64) (c-export :c)) 42)
