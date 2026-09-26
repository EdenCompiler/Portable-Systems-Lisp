(include "../shared.lisp")
(defun answer ()
  (declare (returns u64) (c-export :c))
  (included_helper 41))
