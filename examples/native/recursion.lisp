(defun factorial (number)
  (declare (type u64 number)
           (returns u64)
           (c-export :c))
  (if (< number 2)
      1
      (wrap* number (factorial (wrap- number 1)))))

(defun main ()
  (declare (returns c-int) (c-export :c))
  (if (= (factorial 5) 120) 0 1))
