(defmacro m (pi) '1)
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
