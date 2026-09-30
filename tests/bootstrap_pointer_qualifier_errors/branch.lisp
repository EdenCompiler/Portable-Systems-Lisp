(defun bad (constant mutable)
  (declare (type (ptr u8 :const) constant) (type (ptr u8) mutable)
           (returns (ptr u8 :const)))
  (if t constant mutable))
