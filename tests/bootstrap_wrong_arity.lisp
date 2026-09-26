(defun add (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (wrap+ a b))

(defun answer ()
  (declare (returns u64) (c-export :c))
  (add 42))
