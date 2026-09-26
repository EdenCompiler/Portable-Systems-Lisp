(defun invalid_cast ()
  (declare (returns u8) (c-export :c))
  (wrap-cast u8))
