(defmacro m () (if nil 1 unknown_control))
(defun answer () (declare (returns u64) (c-export :c)) (m))
