(ffi:import-data "c_counter" c-long)
(ffi:export-data "psl_counter" c-long 41)

(defun read_psl_counter ()
  (declare (returns c-long) (c-export :c))
  (deref (ffi:address-of psl_counter)))

(defun increment_c_counter ()
  (declare (returns c-long) (c-export :c))
  (store (ffi:address-of c_counter)
         (wrap+ (deref (ffi:address-of c_counter)) 1)))
