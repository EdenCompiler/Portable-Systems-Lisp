(defun bad (pointer)
  (declare (type (ptr u8 :restrict) pointer) (returns u8))
  (deref pointer))
