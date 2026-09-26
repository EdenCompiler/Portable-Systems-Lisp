;; LIR verifies labels, operation shapes, types, and definitions on every
;; incoming path. It does not consult HIR or SSA instructions.
(include "lir_verify_cfg.lisp")

(defun lir_control_shape_p (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir)))
        (kind (deref (field-pointer op 'kind)))
        (left (deref (field-pointer op 'left)))
        (right (deref (field-pointer op 'right)))
        (target (deref (field-pointer op 'target))))
    (if (= (deref (field-pointer op 'destination)) 0)
        (if (= (deref (field-pointer op 'value)) 0)
            (cond
              ((= kind 100) (if (= left 0) (if (= right 0) (ir_reference_p target (deref (field-pointer arena 'label_count))) 0) 0))
              ((= kind 101) (if (= left 0) (if (= right 0) (ir_reference_p target (deref (field-pointer arena 'label_count))) 0) 0))
              ((= kind 102)
               (if (= (ir_reference_p left (deref (field-pointer arena 'value_count))) 0) 0
                   (if (= (ir_reference_p target (deref (field-pointer arena 'label_count))) 0) 0
                       (if (= (ir_reference_p right (deref (field-pointer arena 'label_count))) 0) 0
                           (ir_types_same_p context (deref (field-pointer arena 'types)) left 0 0)))))
              ((= kind 103)
               (if (= target 0)
                   (if (= right 0)
                       (if (= (ir_reference_p left (deref (field-pointer arena 'value_count))) 0) 0
                           (lir_return_type_p context op)) 0) 0))
              (t 0)) 0) 0)))

(defun lir_catalog_entry_p (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (let ((type (ir_type_at (deref (field-pointer arena 'types)) reference)))
      (if (= (ir_source_type_p context (deref (field-pointer type 'scalar_code))
                               (deref (field-pointer type 'pointee))) 0) 0
          (if (= (deref (field-pointer type 'kind)) 17)
              (if (= (ir_reference_p (deref (field-pointer type 'left)) (wrap- reference 1)) 0) 0
                  (if (= (deref (field-pointer type 'right)) 0) 1
                      (if (= (ir_reference_p (deref (field-pointer type 'right)) (wrap- reference 1)) 0) 0
                          (if (= (deref (field-pointer
                                  (ir_type_at (deref (field-pointer arena 'types)) (deref (field-pointer type 'right))) 'kind)) 17) 1 0))))
              (if (= (deref (field-pointer type 'left)) 0)
                  (if (= (deref (field-pointer type 'right)) 0) 1 0) 0))))))

(defun lir_verify_catalog (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count)) index) 1
      (if (= (lir_catalog_entry_p context index) 0) 0
          (lir_verify_catalog context (wrap+ index 1)))))

(defun lir_value_shape_p (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir)))
        (destination (deref (field-pointer op 'destination))))
    (if (= (ir_reference_p destination (deref (field-pointer arena 'value_count))) 0) 0
        (let ((type (ir_type_at (deref (field-pointer arena 'types)) destination))
              (scalar (ptr-cast (ptr native_scalar_op) op)))
          (if (= (source_types_equal_p context (deref (field-pointer op 'scalar_code))
                   (deref (field-pointer op 'pointee)) (deref (field-pointer type 'scalar_code))
                   (deref (field-pointer type 'pointee))) 0) 0
              (if (= (deref (field-pointer op 'kind)) 104)
                  (if (= (deref (field-pointer type 'kind)) 28)
                      (lir_verify_value_op context scalar) 0)
                  (if (= (deref (field-pointer op 'kind)) (deref (field-pointer type 'kind)))
                      (lir_verify_value_op context scalar) 0)))))))

(defun lir_verify_value_op (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (if (= (deref (field-pointer op 'kind)) 28) 0
        (if (= (deref (field-pointer op 'kind)) 17) 0
            (if (= (ir_op_operands_p op (deref (field-pointer arena 'value_count))) 0) 0
                (if (= (ir_op_metadata_p context op) 0) 0
                    (ir_verify_scalar_type context (deref (field-pointer arena 'types)) op)))))))

(defun lir_verify_shapes (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer arena 'count)) index) 1
        (let ((op (lir_instruction_at arena index)))
          (let ((valid (if (= (deref (field-pointer op 'destination)) 0)
                           (lir_control_shape_p context op) (lir_value_shape_p context op))))
            (if (= valid 0) 0 (lir_verify_shapes context (wrap+ index 1))))))))

(defun lir_verify_call_definitions (arena chain index block remaining)
  (declare (type (ptr native_lir_arena) arena)
           (type usize chain index block remaining) (returns c-int))
  (if (= remaining 0) 1
      (let ((link (ir_type_at (deref (field-pointer arena 'types)) chain)))
        (if (= (lir_value_defined_p arena (deref (field-pointer link 'left)) index block) 0) 0
            (lir_verify_call_definitions arena (deref (field-pointer link 'right)) index block (wrap- remaining 1))))))

(defun lir_verify_defined_operands (context op index block)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op)
           (type usize index block) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir)))
        (kind (deref (field-pointer op 'kind))))
    (cond
      ((= kind 100) 1) ((= kind 101) 1)
      ((= (ir_leaf_kind_p kind) 1) 1)
      ((= kind 7)
       (let ((signature (native_signature_at (deref (field-pointer context 'signatures))
                                            (wrap- (deref (field-pointer op 'target)) 1))))
         (lir_verify_call_definitions arena (deref (field-pointer op 'left)) index block
                                      (deref (field-pointer signature 'arity)))))
      (t (if (= (lir_value_defined_p arena (deref (field-pointer op 'left)) index block) 0) 0
             (if (= (ir_binary_kind_p kind) 1)
                 (lir_value_defined_p arena (deref (field-pointer op 'right)) index block) 1))))))

(defun lir_verify_definitions (context index block)
  (declare (type (ptr native_compile_context) context)
           (type usize index block) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer arena 'count)) index) 1
        (let ((op (lir_instruction_at arena index)))
          (if (= (deref (field-pointer op 'kind)) 100)
              (lir_verify_definitions context (wrap+ index 1) (deref (field-pointer op 'target)))
              (if (= (lir_verify_defined_operands context op index block) 0) 0
                  (lir_verify_definitions context (wrap+ index 1) block)))))))

(defun lir_verify_function_body (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (if (= (deref (field-pointer arena 'error)) 0)
        (if (= (ir_reference_p (deref (field-pointer arena 'count)) (deref (field-pointer arena 'capacity))) 0) 0
            (if (= (ir_reference_p (deref (field-pointer arena 'label_count)) (deref (field-pointer arena 'label_capacity))) 0) 0
                (if (= (lir_verify_catalog context 1) 0) 0
                    (if (= (lir_verify_shapes context 1) 0) 0
                        (progn
                          (lir_clear_blocks arena 1)
                          (if (= (lir_scan_blocks arena 1 0) 0) 0
                              (if (= (lir_verify_ranges arena 1) 0) 0
                                  (if (= (lir_verify_reachability arena 1) 0) 0
                                      (lir_verify_definitions context 1 0))))))))) 0)))

(defun lir_return_type_p (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((signature (deref (field-pointer context 'current_signature)))
        (types (deref (field-pointer (deref (field-pointer context 'lir)) 'types))))
    (if (= (source_types_equal_p context (deref (field-pointer op 'scalar_code))
             (deref (field-pointer op 'pointee))
             (scalar_signature_type_code context signature)
             (scalar_signature_result_pointee context signature)) 0) 0
        (ir_operand_matches_op_p context types (deref (field-pointer op 'left))
                                 (ptr-cast (ptr native_scalar_op) op)))))

(defun lir_entry_p (arena)
  (declare (type (ptr native_lir_arena) arena) (returns c-int))
  (let ((op (lir_instruction_at arena 1)))
    (if (= (deref (field-pointer op 'kind)) 100)
        (if (= (deref (field-pointer op 'target)) 1) 1 0) 0)))

(defun lir_verify_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int) (c-export :c))
  (let ((arena (deref (field-pointer context 'lir))))
    (if (= (ir_reference_p (deref (field-pointer arena 'value_count))
                           (deref (field-pointer arena 'value_capacity))) 0) 0
        (if (= (ir_reference_p (deref (field-pointer arena 'count))
                               (deref (field-pointer arena 'capacity))) 0) 0
            (if (= (lir_entry_p arena) 0) 0 (lir_verify_function_body context))))))
