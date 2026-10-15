(ffi:source "runtime_precise_closure_link.c")
(defun closure_link_marker ()
  (declare (returns u64) (c-export :c)) 42)
