(defun bad (slot)
  (declare (type (ptr (ptr u8 :const)) slot) (returns (ptr u8)))
  (deref slot))
