(defun answer ()
  (declare (returns u64) (c-export :c))
  (let ((x 10)
        (y (wrap+ 2 3)))
    (let ((x (wrap+ x 1))
          (z (wrap+ x y)))
      (progn
        (wrap+ 1 1)
        (wrap+ (wrap+ x z) 16)))))
