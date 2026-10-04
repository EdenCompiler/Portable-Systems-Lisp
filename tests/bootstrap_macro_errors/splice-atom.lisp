(defmacro m (x) `(progn ,@x))
(defun answer () (declare (returns u64) (c-export :c)) (m 42))
