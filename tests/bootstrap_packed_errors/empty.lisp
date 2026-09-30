(defstruct/packed packet)
(defun answer () (declare (returns u64) (c-export :c)) 42)
