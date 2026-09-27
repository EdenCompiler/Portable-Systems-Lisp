;; Templates are snapshots of verified, unoptimized one-block SSA functions.
;; Calls, memory operations, joins, and loops are never copied into callers.

(defun ssa_inline_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (cond
    ((= kind 1) 1) ((= kind 2) 1) ((= kind 19) 1)
    ((= kind 4) 1) ((= kind 5) 1) ((= kind 6) 1)
    ((= kind 8) 1) ((= kind 9) 1) ((= kind 11) 1) ((= kind 12) 1)
    ((= kind 18) 1) ((= kind 21) 1) ((= kind 22) 1) ((= kind 30) 1)
    ((= kind 31) 1)
    (t 0)))

(defun ssa_inline_body_values_p (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'value_count)) index) 1
      (if (= (ssa_inline_kind_p (deref (field-pointer (ssa_value_at arena index) 'kind))) 0) 0
          (ssa_inline_body_values_p arena (wrap+ index 1)))))

(defun ssa_inline_body_p (arena)
  (declare (type (ptr native_ssa_arena) arena) (returns c-int))
  (if (= (deref (field-pointer arena 'block_count)) 1)
      (if (< 12 (deref (field-pointer arena 'value_count))) 0
          (if (= (deref (field-pointer (ssa_block_at arena 1) 'terminator)) 1)
              (ssa_inline_body_values_p arena 1) 0)) 0))

(defun ssa_inline_template_at (context signature reference)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (type usize reference) (returns (ptr native_ssa_value)))
  (pointer+ (deref (field-pointer context 'inline_values))
            (wrap-cast isize (wrap+ (deref (field-pointer signature 'inline_base))
                                    (wrap- reference 1)))))

(defun ssa_inline_save_values (context signature index)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (type usize index) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (if (< (deref (field-pointer arena 'value_count)) index) 1
        (progn
          (ssa_move_record (ptr-cast (ptr u8) (ssa_inline_template_at context signature index))
                           (ptr-cast (ptr u8) (ssa_value_at arena index)) (sizeof 'native_ssa_value))
          (ssa_inline_save_values context signature (wrap+ index 1))))))

(defun ssa_inline_save_body (context signature)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (let ((count (deref (field-pointer arena 'value_count)))
          (used (deref (field-pointer context 'inline_count)))
          (capacity (deref (field-pointer context 'inline_capacity))))
      (if (< capacity used) 0
          (if (< (wrap- capacity used) count) 1
              (progn
                (store (field-pointer signature 'inline_base) used)
                (ssa_inline_save_values context signature 1)
                (store (field-pointer signature 'inline_count) count)
                (store (field-pointer signature 'inline_result)
                       (deref (field-pointer (ssa_block_at arena 1) 'result)))
                (store (field-pointer context 'inline_count) (wrap+ used count))
                1))))))

(defun ssa_inline_template_value_p (context signature index)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (type usize index) (returns c-int))
  (let ((node (ssa_inline_template_at context signature index)))
    (if (= (ssa_inline_kind_p (deref (field-pointer node 'kind))) 0) 0
        (if (= (ir_op_operands_p (ptr-cast (ptr native_scalar_op) node) (wrap- index 1)) 0) 0
            (if (= (ir_op_metadata_p context (ptr-cast (ptr native_scalar_op) node)) 0) 0
                (if (= (deref (field-pointer node 'kind)) 2)
                    (ir_reference_p (wrap-cast usize (deref (field-pointer node 'value)))
                                    (deref (field-pointer signature 'arity))) 1))))))

(defun ssa_inline_template_values_p (context signature index)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer signature 'inline_count)) index) 1
      (if (= (ssa_inline_template_value_p context signature index) 0) 0
          (ssa_inline_template_values_p context signature (wrap+ index 1)))))

(defun ssa_inline_template_p (context signature)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (returns c-int))
  (let ((base (deref (field-pointer signature 'inline_base)))
        (count (deref (field-pointer signature 'inline_count)))
        (used (deref (field-pointer context 'inline_count))))
    (if (= (ptr-address (deref (field-pointer context 'inline_values))) 0) 0
        (if (= (deref (field-pointer signature 'imported)) 1) 0
        (if (= (ir_reference_p count 12) 0) 0
            (if (< (deref (field-pointer context 'inline_capacity)) used) 0
                (if (< used base) 0
                    (if (< (wrap- used base) count) 0
                        (if (= (ir_reference_p (deref (field-pointer signature 'inline_result)) count) 0) 0
                            (ssa_inline_template_values_p context signature 1))))))))))
