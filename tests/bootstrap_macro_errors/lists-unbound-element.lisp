(defmacro m () (list 'wrap+ 1 unknown_list))
(defun answer () (declare (returns u64) (c-export :c)) (m))
