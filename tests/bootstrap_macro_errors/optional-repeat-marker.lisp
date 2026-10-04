(defmacro m (&optional x &optional y) x)
(defun answer () (declare (returns u64) (c-export :c)) (m))
