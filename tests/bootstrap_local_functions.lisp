(defun local_before (value)
  (declare (type u64 value)
           (returns u64))
  (wrap* value 2))

(defun answer ()
  (declare (returns u64) (c-export :c))
  (wrap+ (local_before 20) 2))

(defun local_after ()
  (declare (returns u64))
  42)
