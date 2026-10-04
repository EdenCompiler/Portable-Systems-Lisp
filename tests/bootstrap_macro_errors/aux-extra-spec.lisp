(defmacro m (&aux (x 1 extra)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m))
