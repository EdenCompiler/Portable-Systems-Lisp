(defmacro m (&key ((5 x) 1)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m ))
