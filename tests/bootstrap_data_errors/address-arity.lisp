(ffi:import-data "counter" u64)

(defun invalid-address-arity ()
  (declare (returns (ptr u64)) (c-export :c))
  (ffi:address-of counter counter))
