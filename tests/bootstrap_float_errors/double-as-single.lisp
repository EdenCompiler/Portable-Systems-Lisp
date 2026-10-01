(defun invalid (p)
  (declare (type (ptr f32) p) (returns c-int))
  (store p 1.0d0)
  0)
