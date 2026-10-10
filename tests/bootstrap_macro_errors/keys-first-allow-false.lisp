(defmacro m (x &key y) x)
(defun answer () (declare (returns u64) (c-export :c)) (m 42 :unknown 7 :allow-other-keys nil :allow-other-keys t))
