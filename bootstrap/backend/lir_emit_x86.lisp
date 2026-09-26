(include "x86_stack.lisp")

;; x86-64 consumes flat LIR and virtual-register types only. Every virtual
;; register has a frame slot; this baseline keeps calls and joins simple.

(defun x86_lir_load (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (x86_load_local (deref (field-pointer context 'code)) reference
                  (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))))

(defun x86_lir_normalize (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer op 'scalar_code))))
    (x86_normalize_integer (deref (field-pointer context 'code))
                           (scalar_type_bits code) (scalar_type_signed_p code))))

(defun x86_lir_binary_operands (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (x86_lir_load context (deref (field-pointer op 'left))) 0) 0
      (if (= (x86_save_left (deref (field-pointer context 'code))) 0) 0
          (x86_lir_load context (deref (field-pointer op 'right))))))

(defun x86_lir_binary (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (x86_lir_binary_operands context op) 0) 0
      (let ((kind (deref (field-pointer op 'kind)))
            (code (deref (field-pointer context 'code))))
        (cond
          ((= kind 8) (x86_lir_compare context op kind))
          ((= kind 9) (x86_lir_compare context op kind))
          ((= kind 25)
           (if (= (emit_byte code #x59) 0) 0
               (x86_store_word code (wrap-cast usize (deref (field-pointer op 'value))))))
          ((= kind 27)
           (if (= (x86_scale_offset code (wrap-cast usize (deref (field-pointer op 'value)))) 0) 0
               (x86_combine code 43)))
          (t (if (= (x86_combine code (x86_scalar_operation kind)) 0) 0
                 (x86_lir_normalize context op)))))))

(defun x86_lir_compare (context op kind)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op)
           (type u32 kind) (returns c-int))
  (let ((type (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types))
                         (deref (field-pointer op 'left)))))
    (x86_compare_integer (deref (field-pointer context 'code)) kind
                          (scalar_type_signed_p (deref (field-pointer type 'scalar_code))))))

(defun x86_lir_unary (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (x86_lir_load context (deref (field-pointer op 'left))) 0) 0
      (let ((kind (deref (field-pointer op 'kind)))
            (code (deref (field-pointer context 'code))))
        (cond
          ((= kind 18) (x86_lir_normalize context op))
          ((= kind 20) (x86_load_immediate code 1))
          ((= kind 23) (x86_add_field_offset code (deref (field-pointer op 'value))))
          ((= kind 24)
           (if (= (scalar_type_signed_p (deref (field-pointer op 'scalar_code))) 1)
               (x86_load_signed code (wrap-cast usize (deref (field-pointer op 'value))))
               (x86_load_unsigned code (wrap-cast usize (deref (field-pointer op 'value))))))
          (t 1)))))

(defun x86_lir_push_arguments (context chain remaining)
  (declare (type (ptr native_compile_context) context)
           (type usize chain remaining) (returns c-int))
  (if (= remaining 0) 1
      (let ((link (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) chain)))
        (if (= (x86_lir_push_arguments context (deref (field-pointer link 'right)) (wrap- remaining 1)) 0) 0
            (if (= (x86_lir_load context (deref (field-pointer link 'left))) 0) 0
                (x86_save_left (deref (field-pointer context 'code))))))))

(defun x86_lir_pop_arguments (context remaining)
  (declare (type (ptr native_compile_context) context)
           (type usize remaining) (returns c-int))
  (if (= remaining 0) 1
      (if (= (x86_pop_argument (deref (field-pointer context 'code)) remaining) 0) 0
          (x86_lir_pop_arguments context (wrap- remaining 1)))))

(defun x86_lir_stack_arguments (context chain index)
  (declare (type (ptr native_compile_context) context)
           (type usize chain index) (returns usize))
  (if (< index 7) chain
      (let ((link (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) chain)))
        (if (= (x86_lir_load context (deref (field-pointer link 'left))) 0) 0
            (if (= (x86_store_stack_argument (deref (field-pointer context 'code)) index) 0) 0
                (x86_lir_stack_arguments context (deref (field-pointer link 'right)) (wrap- index 1)))))))

(defun x86_lir_call_arguments (context chain arity)
  (declare (type (ptr native_compile_context) context)
           (type usize chain arity) (returns c-int))
  (let ((register_chain (x86_lir_stack_arguments context chain arity))
        (register_count (if (< 6 arity) (wrap-cast usize 6) arity)))
    (if (= register_chain 0)
        (if (= arity 0) 1 0)
        (if (= (x86_lir_push_arguments context register_chain register_count) 0) 0
            (x86_lir_pop_arguments context register_count)))))

(defun x86_lir_call_reserved (context op target arity bytes)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op)
           (type usize target arity bytes) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (x86_adjust_stack code bytes 1) 0) 0
        (if (= (x86_lir_call_arguments context (deref (field-pointer op 'left)) arity) 0) 0
            (if (= (emit_deferred_call code (deref (field-pointer context 'fixups)) target 0) 0) 0
                (if (= (x86_adjust_stack code bytes 0) 0) 0
                    (x86_lir_normalize context op)))))))

(defun x86_lir_call (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((target (deref (field-pointer op 'target))))
    (let ((function (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1))))
      (let ((arity (deref (field-pointer function 'arity))))
        (let ((count (x86_stack_argument_count arity)))
          ;; Limit the aligned byte reservation to a positive signed imm32.
          (if (< 268435454 count) 0
              (x86_lir_call_reserved context op target arity (x86_stack_argument_bytes count))))))))

(defun x86_lir_value (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 1) (x86_load_immediate code (deref (field-pointer op 'value))))
      ((= kind 19) (x86_load_immediate code (deref (field-pointer op 'value))))
      ((= kind 2)
       (if (= (x86_load_parameter code (wrap-cast usize (deref (field-pointer op 'value)))) 0) 0
           (x86_lir_normalize context op)))
      ((= kind 7) (x86_lir_call context op))
      ((= (ir_binary_kind_p kind) 1) (x86_lir_binary context op))
      (t (x86_lir_unary context op)))))

(defun x86_lir_control (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code)))
        (jumps (deref (field-pointer context 'jumps))))
    (cond
      ((= kind 100)
       (progn
         (store (pointer+ (deref (field-pointer context 'labels))
                           (wrap-cast isize (wrap- (deref (field-pointer op 'target)) 1)))
                (deref (field-pointer code 'length))) 1))
      ((= kind 101)
       (let ((jump (x86_jump_placeholder code)))
         (if (= jump 0) 0
             (record_call_fixup jumps (wrap+ jump 1) (deref (field-pointer op 'target))))))
      ((= kind 102)
       (if (= (x86_lir_load context (deref (field-pointer op 'left))) 0) 0
           (let ((jump (x86_jump_if_zero_placeholder code)))
             (if (= jump 0) 0
                 (if (= (record_call_fixup jumps (wrap+ jump 2) (deref (field-pointer op 'right))) 0) 0
                     (let ((then_jump (x86_jump_placeholder code)))
                       (if (= then_jump 0) 0
                           (record_call_fixup jumps (wrap+ then_jump 1) (deref (field-pointer op 'target))))))))))
      ((= kind 103)
       (if (= (x86_lir_load context (deref (field-pointer op 'left))) 0) 0 (x86_return code)))
      (t 0))))

(defun x86_lir_emit_instructions (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (let ((lir (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer lir 'count)) index) 1
        (let ((op (lir_instruction_at lir index)))
          (if (= (deref (field-pointer op 'destination)) 0)
              (if (= (x86_lir_control context op) 0) 0 (x86_lir_emit_instructions context (wrap+ index 1)))
              (if (= (x86_lir_value context op) 0) 0
                  (if (= (x86_store_local (deref (field-pointer context 'code))
                                          (deref (field-pointer op 'destination))
                                          (deref (field-pointer lir 'value_count))) 0) 0
                      (x86_lir_emit_instructions context (wrap+ index 1)))))))))

(defun x86_lir_patch_jumps (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (if (= index (deref (field-pointer jumps 'count))) 1
        (let ((fixup (call_fixup_at jumps index)))
          (let ((field (deref (field-pointer fixup 'instruction)))
                (target (deref (pointer+ (deref (field-pointer context 'labels))
                                        (wrap-cast isize (wrap- (deref (field-pointer fixup 'target)) 1))))))
            (if (= (patch_i32 (deref (field-pointer context 'code)) field
                              (wrap-cast s32 (wrap- target (wrap+ field 4)))) 0) 0
                (x86_lir_patch_jumps context (wrap+ index 1))))))))

(defun emit_lir_x86_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (store (field-pointer jumps 'count) 0)
    (store (field-pointer jumps 'error) 0)
    (if (= (x86_function_prologue (deref (field-pointer context 'code))
                                  (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))) 0) 0
        (if (= (x86_lir_emit_instructions context 1) 0) 0
            (x86_lir_patch_jumps context 0)))))
