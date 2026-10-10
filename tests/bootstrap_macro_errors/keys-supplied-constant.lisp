(defmacro m (&key (x 1 t)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m ))
