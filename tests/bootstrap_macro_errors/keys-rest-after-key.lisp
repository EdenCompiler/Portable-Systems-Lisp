(defmacro m (&key &rest x) 42)
(defun answer () (declare (returns u64) (c-export :c)) (m ))
