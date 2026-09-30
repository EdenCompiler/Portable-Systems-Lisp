(defun bad (pointer)
  (declare (type (ptr u8 :const :const) pointer) (returns u8))
  (deref pointer))
