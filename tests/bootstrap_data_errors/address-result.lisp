(ffi:import-data "counter" u64)

(defun invalid-address-result ()
  (declare (returns u64) (c-export :c))
  (ffi:address-of counter))
