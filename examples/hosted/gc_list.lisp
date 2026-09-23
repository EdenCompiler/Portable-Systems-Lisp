(defun build-list (remaining tail)
  (declare (type s64 remaining)
           (type value tail)
           (returns value)
           (c-export :c))
  (if (= remaining 0)
      tail
      (build-list (wrap- remaining 1)
                  (cons (box-fixnum remaining) tail))))

(defun count-list (items)
  (declare (type value items)
           (returns s64)
           (c-export :c))
  (if items
      (wrap+ 1 (count-list (cdr items)))
      0))

(defun main ()
  (declare (returns c-int) (c-export :c))
  (let ((items (build-list 400 nil)))
    (collect-garbage)
    (if (= (count-list items) 400) 0 1)))
