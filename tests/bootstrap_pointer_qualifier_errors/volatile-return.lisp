(defun bad (pointer)
  (declare (type (ptr u8 :volatile) pointer) (returns (ptr u8)))
  pointer)
