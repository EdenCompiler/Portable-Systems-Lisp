(defmacro m () (if t))
(defun answer () (declare (returns u64) (c-export :c)) (m))
