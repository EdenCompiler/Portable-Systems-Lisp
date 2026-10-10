(defmacro m (&key (x unknown_key_default)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m ))
