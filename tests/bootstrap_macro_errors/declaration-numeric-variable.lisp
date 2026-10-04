(defmacro m (x) (declare (ignore 7)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
