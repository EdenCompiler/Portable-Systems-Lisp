(defun main ()
  (declare (returns c-int) (c-export :c))
  (let ((items (cons 40 (cons 2 nil))))
    (collect-garbage)
    (if (cdr (cdr items))
        1
        (if (= (unbox-fixnum (car items)) 40) 0 1))))
