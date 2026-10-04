(defmacro m (&aux (x unknown_aux)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m))
