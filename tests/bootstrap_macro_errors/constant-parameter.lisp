(defmacro m (t) t)
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
