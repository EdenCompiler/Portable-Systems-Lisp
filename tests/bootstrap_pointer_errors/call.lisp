(defun f (p) (declare (type (ptr u8) p) (returns (ptr u8))) p)
(defun bad (p) (declare (type (ptr u16) p) (returns (ptr u8))) (f p))
