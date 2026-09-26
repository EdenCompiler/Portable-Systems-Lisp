;; Structural, typed, and dominance checks for the native SSA function.

(include "ssa_verify_cfg.lisp")
(include "ir_verify_shape.lisp")
(include "ir_verify_scalar.lisp")
(include "ir_verify_memory.lisp")

(defun ssa_catalog_matches_p (arena reference value)
  (declare (type (ptr native_ssa_arena) arena)
           (type (ptr native_ssa_value) value)
           (type usize reference) (returns c-int))
  (let ((type (ir_type_at (deref (field-pointer arena 'types)) reference)))
    (if (= (deref (field-pointer value 'kind)) (deref (field-pointer type 'kind)))
        (if (= (deref (field-pointer value 'scalar_code)) (deref (field-pointer type 'scalar_code)))
            (if (= (deref (field-pointer value 'pointee)) (deref (field-pointer type 'pointee)))
                (ssa_catalog_edges_match_p type value) 0) 0) 0)))

(defun ssa_verify_phi (arena reference value)
  (declare (type (ptr native_ssa_arena) arena)
           (type (ptr native_ssa_value) value)
           (type usize reference) (returns c-int))
  (let ((a (deref (field-pointer value 'predecessor_left)))
        (b (deref (field-pointer value 'predecessor_right)))
        (block (deref (field-pointer value 'block)))
        (count (deref (field-pointer arena 'block_count))))
    (if (= (ir_reference_p a count) 0) 0
        (if (= (ir_reference_p b count) 0) 0
            (if (= a b) 0
                (if (= (ssa_incoming_count arena block 1) 2)
                    (if (= (ssa_edge_p arena a block) 0) 0
                        (if (= (ssa_edge_p arena b block) 0) 0
                            (if (= (ssa_verify_use arena (deref (field-pointer value 'left)) reference a) 0) 0
                                (ssa_verify_use arena (deref (field-pointer value 'right)) reference b)))) 0))))))

(defun ssa_verify_value_edges (arena reference value)
  (declare (type (ptr native_ssa_arena) arena)
           (type (ptr native_ssa_value) value)
           (type usize reference) (returns c-int))
  (if (= (deref (field-pointer value 'kind)) 28)
      (if (= (ssa_phi_prefix_p arena (deref (field-pointer value 'block)) reference) 0) 0
          (ssa_verify_phi arena reference value))
      (if (= (deref (field-pointer value 'predecessor_left)) 0)
          (if (= (deref (field-pointer value 'predecessor_right)) 0)
              (if (= (ssa_verify_use arena (deref (field-pointer value 'left)) reference
                                    (deref (field-pointer value 'block))) 0) 0
                  (ssa_verify_use arena (deref (field-pointer value 'right)) reference
                                  (deref (field-pointer value 'block)))) 0) 0)))

(defun ssa_verify_value (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (let ((value (ssa_value_at arena reference)))
      (let ((op (ptr-cast (ptr native_scalar_op) value))
            (block (deref (field-pointer value 'block))))
        (if (= (ir_reference_p block (deref (field-pointer arena 'block_count))) 0) 0
            (if (= (ssa_block_contains_p arena block reference
                     (deref (field-pointer (ssa_block_at arena block) 'first))) 0) 0
                (if (= (ir_op_operands_p op (wrap- reference 1)) 0) 0
                    (if (= (ir_op_metadata_p context op) 0) 0
                        (if (= (ssa_catalog_matches_p arena reference value) 0) 0
                            (if (= (ssa_verify_value_edges arena reference value) 0) 0
                                (ir_verify_scalar_type context (deref (field-pointer arena 'types)) op)))))))))))

(defun ssa_verify_values (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer (deref (field-pointer context 'ssa)) 'value_count)) index) 1
      (if (= (ssa_verify_value context index) 0) 0
          (ssa_verify_values context (wrap+ index 1)))))

(defun ssa_verify_terminal_type (context block index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ssa_block) block)
           (type usize index) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (let ((reference (if (= (deref (field-pointer block 'terminator)) 1)
                         (deref (field-pointer block 'result))
                         (deref (field-pointer block 'condition)))))
      (if (= reference 0) 1
          (if (= (ssa_dominates_p arena (deref (field-pointer (ssa_value_at arena reference) 'block)) index) 0) 0
              (if (= (deref (field-pointer block 'terminator)) 3)
                  (ir_types_same_p context (deref (field-pointer arena 'types)) reference 0 0)
                  (let ((signature (deref (field-pointer context 'current_signature))))
                    (ir_types_same_p context (deref (field-pointer arena 'types)) reference
                                     (scalar_signature_type_code context signature)
                                     (scalar_signature_result_pointee context signature)))))))))

(defun ssa_verify_reachable_blocks (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (if (< (deref (field-pointer arena 'block_count)) index) 1
        (progn
          (ssa_clear_visits arena 1)
          (if (= (ssa_reaches_without arena 1 index 0) 0) 0
              (if (= (ssa_verify_terminal_type context (ssa_block_at arena index) index) 0) 0
                  (ssa_verify_reachable_blocks context (wrap+ index 1))))))))

(defun ssa_verify_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int) (c-export :c))
  (let ((arena (deref (field-pointer context 'ssa))))
    (if (= (deref (field-pointer arena 'error)) 0)
        (if (= (ir_reference_p (deref (field-pointer arena 'value_count))
                               (deref (field-pointer arena 'value_capacity))) 0) 0
            (if (= (ir_reference_p (deref (field-pointer arena 'block_count))
                                   (deref (field-pointer arena 'block_capacity))) 0) 0
                (if (= (ssa_verify_blocks arena 1) 0) 0
                    (if (= (ssa_verify_values context 1) 0) 0
                        (ssa_verify_reachable_blocks context 1))))) 0)))

(defun ssa_catalog_edges_match_p (type value)
  (declare (type (ptr native_ir_type) type)
           (type (ptr native_ssa_value) value) (returns c-int))
  (if (= (deref (field-pointer value 'kind)) 17)
      (if (= (deref (field-pointer type 'left)) (deref (field-pointer value 'left)))
          (if (= (deref (field-pointer type 'right)) (deref (field-pointer value 'right))) 1 0) 0)
      (if (= (deref (field-pointer type 'left)) 0)
          (if (= (deref (field-pointer type 'right)) 0) 1 0) 0)))

(defun ssa_phi_prefix_p (arena block reference)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize block reference) (returns c-int))
  (ssa_phi_prefix_from_p arena (deref (field-pointer (ssa_block_at arena block) 'first)) reference))

(defun ssa_phi_prefix_from_p (arena current reference)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize current reference) (returns c-int))
  (if (= current reference) 1
      (if (= current 0) 0
          (let ((value (ssa_value_at arena current)))
            (if (= (deref (field-pointer value 'kind)) 28)
                (ssa_phi_prefix_from_p arena (deref (field-pointer value 'next)) reference) 0)))))
