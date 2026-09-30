(defstruct/packed packet (tag void))
(defun answer () (declare (returns u64) (c-export :c)) 42)
