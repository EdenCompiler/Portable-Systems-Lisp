(defmacro m (&optional (x 1 supplied extra)) x)
(defun answer () (declare (returns u64) (c-export :c)) (m))
