(defun helper ()
  (declare (returns u64) (c-export :c))
  20)

(defun direct ()
  (declare (returns u64) (c-export :c))
  (helper))

(defun answer ()
  (declare (returns u64) (c-export :c))
  (wrap+ 22 (direct)))
