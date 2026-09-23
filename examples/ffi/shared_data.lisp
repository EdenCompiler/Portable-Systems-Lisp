(ffi:source "data_provider.c")
(ffi:import-data "c_counter" c-long)
(ffi:import-data "c_ratio" c-double)
(ffi:import-data "c_pointer" (ptr u8))
(ffi:export-data "psl_counter" c-long 41)
(ffi:export-data "psl_ratio" c-double 2.5d0)
(ffi:export-data "psl_pointer" (ptr u8) 0)

(defun read_psl_counter ()
  (declare (returns c-long) (c-export :c))
  (deref (ffi:address-of psl_counter)))

(defun increment_c_counter ()
  (declare (returns c-long) (c-export :c))
  (store (ffi:address-of c_counter)
         (wrap+ (deref (ffi:address-of c_counter)) 1)))

(defun read_psl_ratio ()
  (declare (returns c-double) (c-export :c))
  (deref (ffi:address-of psl_ratio)))

(defun replace_c_ratio ()
  (declare (returns c-double) (c-export :c))
  (store (ffi:address-of c_ratio) 3.5d0))

(defun read_pointed_byte ()
  (declare (returns u8) (c-export :c))
  (deref (deref (ffi:address-of c_pointer))))
