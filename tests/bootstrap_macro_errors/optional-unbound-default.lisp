(defmacro m (&optional (x unbound_default)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m))
