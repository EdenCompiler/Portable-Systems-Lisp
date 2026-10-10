(defmacro m (x &key y) x)
(defun answer () (declare (returns u64) (c-export :c)) (m 42 :y))
