(defmacro m (x) 0 (declare (ignore x)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
