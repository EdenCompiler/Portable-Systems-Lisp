(defmacro m (&optional x) x)
(defun answer () (declare (returns u64) (c-export :c)) (m 1 2))
