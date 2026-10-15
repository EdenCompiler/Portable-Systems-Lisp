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

(defun ir_verify_literal_call (context types chain)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types) (type usize chain) (returns c-int))
  (let ((last (ir_type_at types chain)))
    (let ((first (ir_type_at types (deref (field-pointer last 'right))))
          (length (ir_type_at types (deref (field-pointer last 'left)))))
      (let ((address (ir_type_at types (deref (field-pointer first 'left)))))
        (if (= (deref (field-pointer first 'right)) 0)
            (if (= (deref (field-pointer address 'kind)) 35)
                (if (= (deref (field-pointer length 'kind)) 1)
                    1 0) 0) 0)))))

(defun ir_verify_call_type_checked (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((signature (native_signature_at (deref (field-pointer context 'signatures))
                                       (wrap- (deref (field-pointer op 'target)) 1))))
    (if (= (source_types_equal_p context (deref (field-pointer op 'scalar_code))
             (deref (field-pointer op 'pointee))
             (scalar_signature_type_code context signature)
             (scalar_signature_result_pointee context signature)) 0) 0
        (if (= (ir_verify_argument_chain context types (deref (field-pointer op 'left))
                                        signature (deref (field-pointer signature 'arity))) 0) 0
            (if (= (deref (field-pointer signature 'runtime_id)) 14)
                (ir_verify_literal_call context types (deref (field-pointer op 'left))) 1)))))

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
       (if (= code 0)
           (if (if (= (deref (field-pointer child 'scalar_code)) 15) t
                   (= (deref (field-pointer child 'scalar_code)) 16)) 0
               (source_context_code_p context (deref (field-pointer child 'scalar_code)))) 0))
      ((= kind 21) (if (= code 11) (ir_types_same_p context types (deref (field-pointer op 'left)) 2 0) 0))
      ((= kind 22) (if (= code 11) (if (= (deref (field-pointer child 'scalar_code)) 11) 1 0) 0))
      ((= kind 30) (if (= code 2) (if (= (deref (field-pointer child 'scalar_code)) 11) 1 0) 0))
      (t 0))))

(defun ir_verify_closure_callback (context target source)
  (declare (type (ptr native_compile_context) context)
           (type usize target source) (returns c-int))
  (if (= target 0) 0
      (if (< (deref (field-pointer context 'prior_count)) target) 0
          (let ((signature (native_signature_at
                            (deref (field-pointer context 'signatures))
                            (wrap- target 1))))
            (if (= (native_closure_callback_target_p context target source) 1)
                (if (= (deref (field-pointer signature 'imported)) 0)
                    (if (= (deref (field-pointer signature 'arity)) 2)
                        (if (= (scalar_signature_type_code context signature) 15)
                            (if (= (scalar_signature_parameter_code context signature 0) 15)
                                (if (= (scalar_signature_parameter_code context signature 1) 15)
                                    1 0) 0) 0) 0) 0) 0))))
)
(defun ir_verify_function_address (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_scalar_op) op) (returns c-int))
  (if (= (deref (field-pointer op 'scalar_code)) 2)
      (if (= (deref (field-pointer op 'pointee)) 0)
          (if (= (deref (field-pointer op 'value)) 0)
              (if (= (native_lambda_origin_p
                      context (deref (field-pointer op 'source))) 1)
                  (ir_verify_closure_callback
                   context (deref (field-pointer op 'target))
                   (deref (field-pointer op 'source))) 0) 0) 0) 0))

(defun ir_verify_scalar_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer op 'scalar_code))))
    (if (= (ir_result_kind_p code kind) 0) 0
        (if (= (ir_source_type_p context code (deref (field-pointer op 'pointee))) 0) 0
        (cond
          ((= kind 1) (source_word_valid_p code (deref (field-pointer op 'value))))
          ((= kind 2) (ir_verify_parameter_type context op))
          ((= kind 7) (ir_verify_call_type context types op))
          ((= kind 8) (ir_verify_comparison context types op))
          ((= kind 9) (ir_verify_comparison context types op))
          ((= kind 17) (ir_operand_matches_op_p context types (deref (field-pointer op 'left)) op))
          ((= kind 19) (if (= code 0) (if (< 1 (deref (field-pointer op 'value))) 0 1) 0))
          ((= kind 29) (if (= code 12) 1 0))
          ((= kind 35)
           (if (= code 1)
               (if (= (deref (field-pointer op 'pointee)) 0)
                   (native_literal_target_p context (deref (field-pointer op 'target))) 0) 0))
          ((= kind 36) (ir_verify_function_address context op))
      ((= kind 34)
           (let ((target (deref (field-pointer op 'target))))
             (if (= code 11)
                 (if (= target 0) 0
                     (if (< (deref (field-pointer context 'data_count)) target) 0
                         (source_ast_type_equal_p
                          context (deref (field-pointer op 'pointee))
                          (deref (field-pointer
                                  (native_data_import_at context (wrap- target 1))
                                  'type_ast)) 0)))
                 0)))
          ((= kind 18) (ir_verify_unary_type context types op))
          ((= kind 20) (ir_verify_unary_type context types op))
          ((= kind 21) (ir_verify_unary_type context types op))
          ((= kind 22) (ir_verify_unary_type context types op))
          ((= kind 30) (ir_verify_unary_type context types op))
          ((= kind 31)
           (if (= code 12) 0
               (ir_operand_matches_op_p context types (deref (field-pointer op 'left)) op)))
          ((< 22 kind) (ir_verify_memory_type context types op))
          (t (ir_verify_integer_binary context types op)))))))

(defun ir_result_kind_p (code kind)
  (declare (type u32 code kind) (returns c-int))
  (if (= code 12)
      (if (= kind 7) 1 (if (= kind 29) 1 0)) 1))

(defun ir_verify_call_type (context types op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((signature (native_signature_at (deref (field-pointer context 'signatures))
                    (wrap- (deref (field-pointer op 'target)) 1))))
    (if (= (native_runtime_call_signature_p context signature) 0) 0
        (ir_verify_call_type_checked context types op))))
