(defun double-value (value)
  (declare (type u64 value)
           (returns u64)
           (c-export :c))
  (wrap+ value value))

(defun main ()
  (declare (returns c-int) (c-export :c))
  (without-allocation
    (if (= (double-value 21) 42) 0 1)))
