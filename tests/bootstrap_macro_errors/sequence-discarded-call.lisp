(defmacro m () (unknown_sequence_call) '42)
(defun answer () (declare (returns u64) (c-export :c)) (m))
