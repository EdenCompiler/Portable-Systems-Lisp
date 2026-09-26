(defun bad (p q) (declare (type (ptr (ptr u8)) p) (type (ptr u16) q) (returns (ptr u16))) (store p q))
