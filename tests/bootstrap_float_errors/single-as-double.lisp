(defun invalid (p)
  (declare (type (ptr f64) p) (returns c-int))
  (store p 1.0f0)
  0)
