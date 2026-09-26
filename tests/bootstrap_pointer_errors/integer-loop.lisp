(defun bad (p) (declare (type (ptr u8) p) (returns c-int)) (while 0 (store p 1)) 1)
