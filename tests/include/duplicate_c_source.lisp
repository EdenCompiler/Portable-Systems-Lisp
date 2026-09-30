(ffi:source "include_helper.c")
(ffi:source "./include_helper.c")

(defun answer ()
  (declare (returns u64) (c-export :c))
  42)
