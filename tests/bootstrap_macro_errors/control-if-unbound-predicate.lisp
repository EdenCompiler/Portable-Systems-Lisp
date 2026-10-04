(defmacro m () (if unknown_control 1 2))
(defun answer () (declare (returns u64) (c-export :c)) (m))
