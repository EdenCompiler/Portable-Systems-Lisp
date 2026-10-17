(defmacro bad-length-dotted () (length '(a . b)))
(defun bad_length_dotted () (declare (returns u64)) (bad-length-dotted))
