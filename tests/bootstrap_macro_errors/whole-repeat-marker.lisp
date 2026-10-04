(defmacro m (&whole x &whole y) '42)
(defun answer () (declare (returns u64) (c-export :c)) (m))
