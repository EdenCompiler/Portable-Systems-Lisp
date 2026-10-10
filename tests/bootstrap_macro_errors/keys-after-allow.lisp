(defmacro m (&key &allow-other-keys x) 42)
(defun answer () (declare (returns u64) (c-export :c)) (m ))
