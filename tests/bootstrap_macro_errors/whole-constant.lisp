(defmacro m (&whole t) '42)
(defun answer () (declare (returns u64) (c-export :c)) (m))
