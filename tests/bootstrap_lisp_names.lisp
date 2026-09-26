(defun helper-one (some-value)
  (declare (type u64 some-value) (returns u64))
  some-value)

(defun answer ()
  (declare (returns u64) (c-export :c))
  (let ((local-value (helper-one 41)))
    (wrap+ local-value 1)))
