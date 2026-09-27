(defun bad (memory) (declare (type (ptr void) memory) (returns (ptr void)))
  (pointer+ memory 1))
