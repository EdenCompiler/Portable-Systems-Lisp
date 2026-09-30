(defstruct/packed packet (tag u8) (tag u64))
(defun answer () (declare (returns u64) (c-export :c)) 42)
