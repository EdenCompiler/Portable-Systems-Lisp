;; Shared typed scalar operation checks. Reference bounds and CFG dominance
;; are verified by each representation before these routines inspect types.

(defun ir_verify_integer_binary (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((code (deref (field-pointer op 'scalar_code)))
        (kind (deref (field-pointer op 'kind))))
    (if (= (scalar_binary_code_p code (if (= kind 12) 1 0)) 0) 0
        (if (= (ir_operand_matches_op_p context types (deref (field-pointer op 'left)) op) 0) 0
            (ir_operand_matches_op_p context types (deref (field-pointer op 'right)) op)))))

(defun ir_verify_comparison (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((left (ir_type_at types (deref (field-pointer op 'left)))))
    (if (= (deref (field-pointer op 'scalar_code)) 0)
        (if (= (scalar_valid_code_p (deref (field-pointer left 'scalar_code))) 0) 0
            (ir_types_same_p context types (deref (field-pointer op 'right))
                             (deref (field-pointer left 'scalar_code)) 0))
        0)))

(defun ir_verify_argument_chain (context types chain signature remaining)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_signature) signature)
           (type usize chain remaining) (returns c-int))
  (if (= remaining 0) (if (= chain 0) 1 0)
      (if (= chain 0) 0
          (let ((link (ir_type_at types chain)))
            (if (= (deref (field-pointer link 'kind)) 17)
                (if (= (ir_types_same_p context types (deref (field-pointer link 'left))
                         (scalar_signature_parameter_code context signature (wrap- remaining 1))
                         (scalar_signature_parameter_pointee context signature (wrap- remaining 1))) 0) 0
                    (ir_verify_argument_chain context types (deref (field-pointer link 'right))
                                              signature (wrap- remaining 1)))
                0)))))

(defun ir_verify_call_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((signature (native_signature_at (deref (field-pointer context 'signatures))
                                       (wrap- (deref (field-pointer op 'target)) 1))))
    (if (= (source_types_equal_p context (deref (field-pointer op 'scalar_code))
             (deref (field-pointer op 'pointee))
             (scalar_signature_type_code context signature)
             (scalar_signature_result_pointee context signature)) 0) 0
        (ir_verify_argument_chain context types (deref (field-pointer op 'left))
                                  signature (deref (field-pointer signature 'arity))))))

(defun ir_verify_parameter_type (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((index (wrap-cast usize (deref (field-pointer op 'value)))))
    (if (= index 0) 0
        (if (< (deref (field-pointer context 'current_arity)) index) 0
            (source_types_equal_p context (deref (field-pointer op 'scalar_code))
                                  (deref (field-pointer op 'pointee))
                                  (scalar_current_parameter_code context index)
                                  (scalar_signature_parameter_pointee
                                   context (deref (field-pointer context 'current_signature))
                                   (wrap- index 1)))))))

(defun ir_verify_unary_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer op 'scalar_code)))
        (child (ir_type_at types (deref (field-pointer op 'left)))))
    (cond
      ((= kind 18)
       (if (= (scalar_valid_code_p code) 0) 0
           (scalar_valid_code_p (deref (field-pointer child 'scalar_code)))))
      ((= kind 20)
       (if (= code 0) (source_valid_code_p (deref (field-pointer child 'scalar_code))) 0))
      ((= kind 21) (if (= code 11) (ir_types_same_p context types (deref (field-pointer op 'left)) 2 0) 0))
      ((= kind 22) (if (= code 11) (if (= (deref (field-pointer child 'scalar_code)) 11) 1 0) 0))
      (t 0))))

(defun ir_verify_scalar_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer op 'scalar_code))))
    (if (= (ir_source_type_p context code (deref (field-pointer op 'pointee))) 0) 0
        (cond
          ((= kind 1) (scalar_word_valid_p code (deref (field-pointer op 'value))))
          ((= kind 2) (ir_verify_parameter_type context op))
          ((= kind 7) (ir_verify_call_type context types op))
          ((= kind 8) (ir_verify_comparison context types op))
          ((= kind 9) (ir_verify_comparison context types op))
          ((= kind 17) (ir_operand_matches_op_p context types (deref (field-pointer op 'left)) op))
          ((= kind 19) (if (= code 0) (if (< 1 (deref (field-pointer op 'value))) 0 1) 0))
          ((= kind 18) (ir_verify_unary_type context types op))
          ((= kind 20) (ir_verify_unary_type context types op))
          ((= kind 21) (ir_verify_unary_type context types op))
          ((= kind 22) (ir_verify_unary_type context types op))
          ((< 22 kind) (ir_verify_memory_type context types op))
          (t (ir_verify_integer_binary context types op))))))
