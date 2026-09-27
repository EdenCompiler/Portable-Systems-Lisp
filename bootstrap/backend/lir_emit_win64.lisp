(include "win64_probe.lisp")
(include "win64_arguments.lisp")

;; Windows consumes the same verified LIR as SysV. RSP is fixed throughout
;; the body, so a frame scratch word replaces operand pushes.
(defun win64_lir_load (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns c-int))
  (win64_load_local (deref (field-pointer context 'code))
                    (deref (field-pointer context 'backend_outgoing_size)) reference
                    (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))))

(defun win64_lir_scratch (context opcode)
  (declare (type (ptr native_compile_context) context) (type u64 opcode) (returns c-int))
  (win64_frame_access (deref (field-pointer context 'code)) opcode
    (wrap+ (deref (field-pointer context 'backend_outgoing_size))
           (wrap+ 32 (wrap* 8 (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count)))))))

(defun win64_lir_binary_operands (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (win64_lir_load context (deref (field-pointer op 'left))) 0) 0
      (if (= (win64_lir_scratch context #x858948) 0) 0
          (win64_lir_load context (deref (field-pointer op 'right))))))

(defun win64_lir_compare (context op kind)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (type u32 kind) (returns c-int))
  (let ((type (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types))
                          (deref (field-pointer op 'left)))))
    (if (= (win64_lir_scratch context #x8d8b48) 0) 0 ; mov rcx, scratch
        (x86_compare_registers (deref (field-pointer context 'code)) kind
                               (scalar_type_signed_p (deref (field-pointer type 'scalar_code)))))))

(defun win64_lir_binary (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (win64_lir_binary_operands context op) 0) 0
      (let ((kind (deref (field-pointer op 'kind)))
            (code (deref (field-pointer context 'code))))
        (cond
          ((= kind 8) (win64_lir_compare context op kind))
          ((= kind 9) (win64_lir_compare context op kind))
          ((= kind 25)
           (if (= (win64_lir_scratch context #x8d8b48) 0) 0
               (x86_store_word code (wrap-cast usize (deref (field-pointer op 'value))))))
          ((= kind 27)
           (if (= (x86_scale_offset code (wrap-cast usize (deref (field-pointer op 'value)))) 0) 0
               (if (= (win64_lir_scratch context #x8d8b48) 0) 0
                   (x86_arithmetic_instruction code 43))))
          (t (if (= (win64_lir_scratch context #x8d8b48) 0) 0
                 (if (= (x86_arithmetic_instruction code (x86_scalar_operation kind)) 0) 0
                     (x86_lir_normalize context op))))))))

(defun win64_lir_unary (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (win64_lir_load context (deref (field-pointer op 'left))) 0) 0
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

(defun win64_lir_arguments (context chain index)
  (declare (type (ptr native_compile_context) context)
           (type usize chain index) (returns c-int))
  (if (= index 0) 1
      (let ((link (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) chain)))
        (if (= (win64_lir_load context (deref (field-pointer link 'left))) 0) 0
            (if (= (if (< index 5)
                       (win64_register_argument (deref (field-pointer context 'code)) index)
                       (win64_stack_argument (deref (field-pointer context 'code)) index
                                             (deref (field-pointer context 'backend_outgoing_size)))) 0) 0
                (win64_lir_arguments context (deref (field-pointer link 'right)) (wrap- index 1)))))))

(defun win64_lir_call (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((target (deref (field-pointer op 'target))))
    (let ((function (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1))))
      (store (field-pointer function 'referenced) 1)
      (if (= (win64_lir_arguments context (deref (field-pointer op 'left))
                                  (deref (field-pointer function 'arity))) 0) 0
          (if (= (emit_deferred_call (deref (field-pointer context 'code))
                                      (deref (field-pointer context 'fixups)) target 0) 0) 0
              (x86_lir_normalize context op))))))

(defun win64_lir_value (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 1) (x86_load_immediate code (deref (field-pointer op 'value))))
      ((= kind 19) (x86_load_immediate code (deref (field-pointer op 'value))))
      ((= kind 2)
       (if (= (win64_load_parameter code
                 (deref (field-pointer context 'backend_outgoing_size))
                 (deref (field-pointer context 'backend_frame_size))
                 (wrap-cast usize (deref (field-pointer op 'value)))) 0) 0
           (x86_lir_normalize context op)))
      ((= kind 7) (win64_lir_call context op))
      ((= kind 29) 1)
      ((= (ir_binary_kind_p kind) 1) (win64_lir_binary context op))
      (t (win64_lir_unary context op)))))

(defun win64_lir_control (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code)))
        (jumps (deref (field-pointer context 'jumps))))
    (cond
      ((= kind 100)
       (progn (store (pointer+ (deref (field-pointer context 'labels))
                              (wrap-cast isize (wrap- (deref (field-pointer op 'target)) 1)))
                     (deref (field-pointer code 'length))) 1))
      ((= kind 101)
       (let ((jump (x86_jump_placeholder code)))
         (if (= jump 0) 0
             (record_call_fixup jumps (wrap+ jump 1) (deref (field-pointer op 'target))))))
      ((= kind 102)
       (if (= (win64_lir_load context (deref (field-pointer op 'left))) 0) 0
           (let ((jump (x86_jump_if_zero_placeholder code)))
             (if (= jump 0) 0
                 (if (= (record_call_fixup jumps (wrap+ jump 2) (deref (field-pointer op 'right))) 0) 0
                     (let ((then_jump (x86_jump_placeholder code)))
                       (if (= then_jump 0) 0
                           (record_call_fixup jumps (wrap+ then_jump 1) (deref (field-pointer op 'target))))))))))
      ((= kind 103)
       (if (= (deref (field-pointer op 'scalar_code)) 12)
           (win64_return code (deref (field-pointer context 'backend_frame_size)))
           (if (= (win64_lir_load context (deref (field-pointer op 'left))) 0) 0
               (win64_return code (deref (field-pointer context 'backend_frame_size))))))
      (t 0))))

(defun win64_lir_emit_instructions (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((lir (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer lir 'count)) index) 1
        (let ((op (lir_instruction_at lir index)))
          (if (= (deref (field-pointer op 'destination)) 0)
              (if (= (win64_lir_control context op) 0) 0
                  (win64_lir_emit_instructions context (wrap+ index 1)))
              (if (= (win64_lir_value context op) 0) 0
                  (if (= (win64_lir_store_result context op) 0) 0
                      (win64_lir_emit_instructions context (wrap+ index 1)))))))))

(defun win64_lir_store_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (deref (field-pointer op 'scalar_code)) 12) 1
      (win64_store_local (deref (field-pointer context 'code))
                         (deref (field-pointer context 'backend_outgoing_size))
                         (deref (field-pointer op 'destination))
                         (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count)))))

(defun win64_lir_max_outgoing (context index largest)
  (declare (type (ptr native_compile_context) context)
           (type usize index largest) (returns usize))
  (let ((lir (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer lir 'count)) index) largest
        (let ((op (lir_instruction_at lir index)))
          (if (= (deref (field-pointer op 'kind)) 7)
              (let ((function (native_function_at (deref (field-pointer context 'functions))
                                                 (wrap- (deref (field-pointer op 'target)) 1))))
                (let ((bytes (win64_outgoing_bytes (deref (field-pointer function 'arity)))))
                  (win64_lir_max_outgoing context (wrap+ index 1)
                    (if (< largest bytes) bytes largest))))
              (win64_lir_max_outgoing context (wrap+ index 1) largest))))))

(defun emit_lir_win64_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int) (c-export :c))
  (let ((jumps (deref (field-pointer context 'jumps)))
        (outgoing (win64_lir_max_outgoing context 1 32)))
    (store (field-pointer jumps 'count) 0)
    (store (field-pointer jumps 'error) 0)
    (let ((frame (win64_frame_bytes
                   (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))
                   outgoing)))
      (if (= frame 0) 0
          (progn
            (store (field-pointer context 'backend_frame_size) frame)
            (store (field-pointer context 'backend_outgoing_size) outgoing)
            (let ((prologue (win64_function_prologue (deref (field-pointer context 'code))
                                                     frame outgoing)))
              (if (= prologue 0) 0
                  (progn
                    (store (field-pointer context 'backend_prologue_size) prologue)
                    (if (= (win64_lir_emit_instructions context 1) 0) 0
                        (x86_lir_patch_jumps context 0))))))))))
