(defun bad (pointer)
  (declare (type (ptr u8 :const) pointer) (returns u8))
  (store (pointer+ pointer 1) 1))
