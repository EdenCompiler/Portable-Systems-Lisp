(defmacro m (x) (declare ignore) x)
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
