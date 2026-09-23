(defun put-byte (value)
  (declare (type u8 value)
           (returns u8)
           (c-export :c))
  (store (ptr-from-address (ptr u8 :volatile) #x10000000) value))

(defun main ()
  (declare (returns c-int) (c-export :c))
  (if (= (wrap+ 7 5) 12)
      (progn
        (put-byte 80)
        0)
      (progn
        (put-byte 70)
        1)))
