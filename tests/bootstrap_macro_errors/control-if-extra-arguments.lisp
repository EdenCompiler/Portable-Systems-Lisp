(defmacro m () (if t 1 2 3))
(defun answer () (declare (returns u64) (c-export :c)) (m))
