(defun bad (p n) (declare (type (ptr u8) p) (type usize n) (returns (ptr u8))) (pointer+ p n))
