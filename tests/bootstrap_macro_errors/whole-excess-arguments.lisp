(defmacro m (&whole x) '42)
(defun answer () (declare (returns u64) (c-export :c)) (m 1))
