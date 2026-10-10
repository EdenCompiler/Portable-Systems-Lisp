(defmacro m (&key ((:x x extra) 1)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m ))
