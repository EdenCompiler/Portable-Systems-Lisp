;; Shared source type helpers for the native IR verifiers.

(defun ir_types_same_p (context types reference code pointee)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type usize reference pointee)
           (type u32 code) (returns c-int))
  (let ((type (ir_type_at types reference)))
    (source_types_equal_p context (deref (field-pointer type 'scalar_code))
                          (deref (field-pointer type 'pointee)) code pointee)))

(defun ir_operand_matches_op_p (context types reference op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op)
           (type usize reference) (returns c-int))
  (ir_types_same_p context types reference (deref (field-pointer op 'scalar_code))
                   (deref (field-pointer op 'pointee))))

(defun ir_source_type_p (context code pointee)
  (declare (type (ptr native_compile_context) context)
           (type u32 code) (type usize pointee) (returns c-int))
  (if (= code 11)
      (if (= (source_type_reference_p context pointee) 0) 0
          (if (= (source_type_size context pointee) 0) 0 1))
      (if (= pointee 0)
          (if (= code 0) 1 (scalar_valid_code_p code)) 0)))
