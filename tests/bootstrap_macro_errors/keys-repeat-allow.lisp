(defmacro m (&key &allow-other-keys &allow-other-keys) 42)
(defun answer () (declare (returns u64) (c-export :c)) (m ))
