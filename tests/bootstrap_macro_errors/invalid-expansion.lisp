(defmacro m (x) `(undefined_target_function ,x))
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
