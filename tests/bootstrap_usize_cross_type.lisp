(defun source_u64 ()
  (declare (returns u64))
  42)

(defun answer_size ()
  (declare (returns usize) (c-export :c))
  (source_u64))
