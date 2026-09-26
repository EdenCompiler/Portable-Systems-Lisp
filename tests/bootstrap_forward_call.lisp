(defun answer ()
  (declare (returns u64) (c-export :c))
  (later 21))

(defun later (value)
  (declare (type u64 value)
           (returns u64))
  (wrap* value 2))
