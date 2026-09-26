(defun factorial (n)
  (declare (type u64 n)
           (returns u64))
  (if (= n 0)
      1
      (wrap* n (factorial (wrap- n 1)))))

(defun answer ()
  (declare (returns u64) (c-export :c))
  (wrap+ (factorial 4) 18))
