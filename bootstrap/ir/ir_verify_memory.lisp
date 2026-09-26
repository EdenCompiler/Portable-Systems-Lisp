;; Memory types and layout facts are shared by SSA and LIR verifiers.

(defun ir_verify_field_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((index (deref (field-pointer op 'target)))
        (layouts (source_layouts context))
        (left (ir_type_at types (deref (field-pointer op 'left)))))
    (if (= index 0) 0
        (if (< (deref (field-pointer layouts 'field_count)) index) 0
            (if (= (deref (field-pointer left 'scalar_code)) 11)
                (let ((field (native_field_at layouts (wrap- index 1))))
                  (if (= index (source_find_field context (deref (field-pointer left 'pointee))
                                                  (deref (field-pointer field 'name))))
                      (if (= (deref (field-pointer op 'value)) (wrap-cast u64 (deref (field-pointer field 'offset))))
                          (if (= (deref (field-pointer op 'scalar_code)) 11)
                              (source_ast_type_equal_p context (deref (field-pointer op 'pointee))
                                                       (deref (field-pointer field 'type_ast)) 0) 0) 0) 0))
                0)))))

(defun ir_verify_access_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((left (ir_type_at types (deref (field-pointer op 'left))))
        (signatures (deref (field-pointer context 'signatures))))
    (if (= (deref (field-pointer left 'scalar_code)) 11)
        (let ((type (deref (field-pointer left 'pointee))))
          (if (= (source_types_equal_p context (deref (field-pointer op 'scalar_code))
                   (deref (field-pointer op 'pointee)) (scalar_type_code signatures type)
                   (source_type_pointee signatures type)) 0) 0
              (if (= (deref (field-pointer op 'value)) (wrap-cast u64 (source_type_size context type)))
                  (if (= (deref (field-pointer op 'kind)) 24) 1
                      (ir_operand_matches_op_p context types (deref (field-pointer op 'right)) op)) 0))) 0)))

(defun ir_verify_pointer_add_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (if (= (deref (field-pointer op 'scalar_code)) 11)
      (if (= (ir_operand_matches_op_p context types (deref (field-pointer op 'left)) op) 0) 0
          (if (= (ir_types_same_p context types (deref (field-pointer op 'right)) 10 0) 0) 0
              (if (= (deref (field-pointer op 'value))
                     (wrap-cast u64 (source_type_size context (deref (field-pointer op 'pointee))))) 1 0))) 0))

(defun ir_verify_memory_type (context types op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind))))
    (cond
      ((= kind 23) (ir_verify_field_type context types op))
      ((= kind 24) (ir_verify_access_type context types op))
      ((= kind 25) (ir_verify_access_type context types op))
      ((= kind 27) (ir_verify_pointer_add_type context types op))
      ((= kind 28)
       (if (= (ir_operand_matches_op_p context types (deref (field-pointer op 'left)) op) 0) 0
           (ir_operand_matches_op_p context types (deref (field-pointer op 'right)) op)))
      ((= kind 104) (ir_operand_matches_op_p context types (deref (field-pointer op 'left)) op))
      (t 0))))
