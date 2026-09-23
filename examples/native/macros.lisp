(defmacro squared (value)
  `(wrap* ,value ,value))

(defun main ()
  (declare (returns c-int) (c-export :c))
  (let ((number 7))
    (if (= (squared number) 49) 0 1)))
