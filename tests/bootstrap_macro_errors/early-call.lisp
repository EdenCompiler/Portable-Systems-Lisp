(defun answer () (declare (returns u64) (c-export :c)) (m 42))
(defmacro m (x) x)
