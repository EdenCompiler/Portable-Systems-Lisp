(ffi:import-data "c_counter" u64)
(ffi:import-data "MixedCaseData" u32)
(ffi:import-data "unused_counter" u64)

(defun read_counter ()
  (declare (returns u64) (c-export :c))
  (deref (ffi:address-of c_counter)))

(defun increment_counter ()
  (declare (returns u64) (c-export :c))
  (store (ffi:address-of c_counter)
         (wrap+ (deref (ffi:address-of c_counter)) 1))
  (deref (ffi:address-of c_counter)))

(defun read_mixed_case_data ()
  (declare (returns u32) (c-export :c))
  (deref (ffi:address-of "MixedCaseData")))
