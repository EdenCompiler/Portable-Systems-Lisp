(defmacro bad-length-type () (length 1))
(defun bad_length_type () (declare (returns u64)) (bad-length-type))
