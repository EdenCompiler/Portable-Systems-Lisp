(defmacro m (x) (declare (ignorable (x))) x)
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
