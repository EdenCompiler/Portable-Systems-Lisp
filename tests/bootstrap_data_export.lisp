(ffi:import-data "c_counter" u64)
(ffi:export-data "psl_counter" u64 41)
(ffi:export-data "MixedCaseExport" u32 #x89abcdef)
(ffi:export-data "psl_signed" s32 -17)
(ffi:export-data "psl_null" (ptr u8) 0)
(ffi:export-data "unreferenced_export" u16 #x1234)

(defun read_psl_counter ()
  (declare (returns u64) (c-export :c))
  (deref (ffi:address-of psl_counter)))

(defun replace_psl_counter (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (store (ffi:address-of psl_counter) value))

(defun read_mixed_export ()
  (declare (returns u32) (c-export :c))
  (deref (ffi:address-of "MixedCaseExport")))

(defun increment_imported_counter ()
  (declare (returns u64) (c-export :c))
  (store (ffi:address-of c_counter)
         (wrap+ (deref (ffi:address-of c_counter)) 1)))
