(defmacro bad-second-type () (second 1))
(defun bad_second_type () (declare (returns u64)) (bad-second-type))
