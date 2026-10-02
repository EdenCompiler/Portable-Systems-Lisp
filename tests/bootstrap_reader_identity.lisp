(psl.ffi:import-function "identity_c" ((value psl::u64)) -> psl:|U64|)

(common-lisp::defun identity_helper (value)
  (cl::declare (cl::type psl::u64 value) (psl::returns psl:|U64|))
  (psl::wrap+ |VALUE| 2))

(|DEFUN| identity_qualified (value)
  (|DECLARE| (|TYPE| |U64| value) (|RETURNS| psl::u64) (|C-EXPORT| :c))
  (common-lisp::if 0
      (|LET| ((temporary (|IDENTITY_HELPER| |VALUE|)))
        (psl:|WRAP+| |TEMPORARY| (psl.ffi::call identity_c 3)))
      999))

(defun identity_qualified_load (pointer)
  (declare (type (psl:|PTR| psl::u64 :|CONST| :|VOLATILE|) pointer)
           (returns psl:u64) (c-export :c))
  (psl::wrap+ (psl:|DEREF| |POINTER|) 1))
