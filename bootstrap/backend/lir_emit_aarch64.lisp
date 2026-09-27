(include "aarch64_frame.lisp")
(include "aarch64_branches.lisp")

(defun a64_lir_load (context register reference)
  (declare (type (ptr native_compile_context) context) (type u64 register)
           (type usize reference) (returns c-int))
  (a64_load_frame (deref (field-pointer context 'code)) register (a64_local_offset reference) 1))

(defun a64_lir_compare (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((type (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types))
                         (deref (field-pointer op 'left))))
        (code (deref (field-pointer context 'code))))
    (let ((condition (if (= (deref (field-pointer op 'kind)) 8) (wrap-cast u64 1)
                         (if (= (scalar_type_signed_p (deref (field-pointer type 'scalar_code))) 1)
                             (wrap-cast u64 10) (wrap-cast u64 2)))))
      (if (= (a64_register_op code #xeb000000 31 9 10) 0) 0
          (a64_word code (wrap+ #x9a9f07e9 (wrap* condition 4096)))))))

(defun a64_binary_opcode (kind)
  (declare (type u32 kind) (returns u64))
  (cond
    ((= kind 4) #x8b000000) ((= kind 5) #xcb000000) ((= kind 6) #x9b007c00)
    ((= kind 11) #x8a000000) ((= kind 12) #x9ac02400)
    (t 0)))

(defun a64_lir_pointer_add (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (a64_immediate code 11 (deref (field-pointer op 'value))) 0) 0
        (if (= (a64_register_op code #x9b007c00 10 10 11) 0) 0
            (a64_register_op code #x8b000000 9 9 10)))))

(defun a64_lir_store (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (a64_memory code (wrap-cast usize (deref (field-pointer op 'value))) 0 1 10 9) 0) 0
        (a64_register_op code #xaa000000 9 31 10))))

(defun a64_lir_binary (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (if (= (a64_lir_load context 9 (deref (field-pointer op 'left))) 0) 0
      (if (= (a64_lir_load context 10 (deref (field-pointer op 'right))) 0) 0
          (let ((kind (deref (field-pointer op 'kind)))
                (code (deref (field-pointer context 'code))))
            (cond
              ((= kind 8) (a64_lir_compare context op))
              ((= kind 9) (a64_lir_compare context op))
              ((= kind 25) (a64_lir_store context op))
              ((= kind 27) (a64_lir_pointer_add context op))
              (t (if (= (a64_register_op code (a64_binary_opcode kind) 9 9 10) 0) 0
                     (a64_normalize code 9 (deref (field-pointer op 'scalar_code))))))))))

(defun a64_lir_unary (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (if (= (a64_lir_load context 9 (deref (field-pointer op 'left))) 0) 0
      (let ((code (deref (field-pointer context 'code)))
            (kind (deref (field-pointer op 'kind))))
        (cond
          ((= kind 18) (a64_normalize code 9 (deref (field-pointer op 'scalar_code))))
          ((= kind 20) (a64_immediate code 9 1))
          ((= kind 23)
           (if (= (a64_immediate code 10 (deref (field-pointer op 'value))) 0) 0
               (a64_register_op code #x8b000000 9 9 10)))
          ((= kind 24) (a64_memory code (wrap-cast usize (deref (field-pointer op 'value)))
                                   (scalar_type_signed_p (deref (field-pointer op 'scalar_code))) 0 9 9))
          (t 1)))))

(defun a64_lir_arguments (context chain index)
  (declare (type (ptr native_compile_context) context) (type usize chain index) (returns c-int))
  (if (= index 0) 1
      (let ((link (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) chain)))
        (let ((reference (deref (field-pointer link 'left))))
          (if (< 8 index)
              (if (= (a64_lir_load context 9 reference) 0) 0
                  (if (= (a64_store_stack_argument (deref (field-pointer context 'code)) 9 index) 0) 0
                      (a64_lir_arguments context (deref (field-pointer link 'right)) (wrap- index 1))))
              (if (= (a64_lir_load context (wrap-cast u64 (wrap- index 1)) reference) 0) 0
                  (a64_lir_arguments context (deref (field-pointer link 'right)) (wrap- index 1))))))))

(defun a64_lir_call_reserved (context op target arity bytes)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (type usize target arity bytes) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (a64_adjust_stack code bytes 1) 0) 0
        (if (= (a64_lir_arguments context (deref (field-pointer op 'left)) arity) 0) 0
            (if (= (a64_deferred_call code (deref (field-pointer context 'fixups)) target) 0) 0
                (if (= (a64_adjust_stack code bytes 0) 0) 0
                    (if (= (deref (field-pointer op 'scalar_code)) 12) 1
                        (if (= (a64_register_op code #xaa000000 9 31 0) 0) 0
                            (a64_normalize code 9 (deref (field-pointer op 'scalar_code)))))))))))

(defun a64_lir_call (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((target (deref (field-pointer op 'target))))
    (let ((function (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1))))
      (let ((arity (deref (field-pointer function 'arity))))
        (if (< 134217719 arity) 0
            (progn
              (store (field-pointer function 'referenced) 1)
              (a64_lir_call_reserved context op target arity
                (if (< 8 arity) (wrap* 8 (bits-and (wrap- arity 7) (wrap- 0 2)))
                    (wrap-cast usize 0)))))))))

(defun a64_lir_value (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 1) (a64_immediate code 9 (deref (field-pointer op 'value))))
      ((= kind 19) (a64_immediate code 9 (deref (field-pointer op 'value))))
      ((= kind 2)
       (if (= (a64_load_parameter code 9 (wrap-cast usize (deref (field-pointer op 'value)))) 0) 0
           (a64_normalize code 9 (deref (field-pointer op 'scalar_code)))))
      ((= kind 7) (a64_lir_call context op))
      ((= kind 29) 1)
      ((= (ir_binary_kind_p kind) 1) (a64_lir_binary context op))
      (t (a64_lir_unary context op)))))

(defun a64_lir_jump (context target base)
  (declare (type (ptr native_compile_context) context) (type usize target) (type u64 base)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (let ((position (deref (field-pointer code 'length))))
      (if (= (record_call_fixup (deref (field-pointer context 'jumps)) position target) 0) 0
          (a64_word code base)))))

(defun a64_lir_control (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 100)
       (store (pointer+ (deref (field-pointer context 'labels))
                        (wrap-cast isize (wrap- (deref (field-pointer op 'target)) 1)))
              (deref (field-pointer code 'length))) 1)
      ((= kind 101) (a64_lir_jump context (deref (field-pointer op 'target)) #x14000000))
      ((= kind 102)
       (if (= (a64_lir_load context 9 (deref (field-pointer op 'left))) 0) 0
           (if (= (a64_lir_jump context (deref (field-pointer op 'right)) #xb4000009) 0) 0
               (a64_lir_jump context (deref (field-pointer op 'target)) #x14000000))))
      ((= kind 103)
       (if (= (deref (field-pointer op 'scalar_code)) 12) (a64_return code)
           (if (= (a64_lir_load context 0 (deref (field-pointer op 'left))) 0) 0 (a64_return code))))
      (t 0))))

(defun a64_lir_store_result (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (if (= (deref (field-pointer op 'scalar_code)) 12) 1
      (a64_store_frame (deref (field-pointer context 'code)) 9
                       (a64_local_offset (deref (field-pointer op 'destination))))))

(defun a64_lir_emit_instructions (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((lir (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer lir 'count)) index) 1
        (let ((op (lir_instruction_at lir index)))
          (if (= (deref (field-pointer op 'destination)) 0)
              (if (= (a64_lir_control context op) 0) 0 (a64_lir_emit_instructions context (wrap+ index 1)))
              (if (= (a64_lir_value context op) 0) 0
                  (if (= (a64_lir_store_result context op) 0) 0
                      (a64_lir_emit_instructions context (wrap+ index 1)))))))))

(defun a64_lir_patch_jump (context fixup)
  (declare (type (ptr native_compile_context) context) (type (ptr native_call_fixup) fixup)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (position (deref (field-pointer fixup 'instruction))))
    (let ((base (read_u32_le (pointer+ (deref (field-pointer code 'data)) (wrap-cast isize position))))
          (destination (deref (pointer+ (deref (field-pointer context 'labels))
                                       (wrap-cast isize (wrap- (deref (field-pointer fixup 'target)) 1))))))
      (a64_patch_branch code position destination base (if (= base #x14000000) 26 (wrap-cast u32 19))))))

(defun a64_lir_patch_jumps (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (if (= index (deref (field-pointer jumps 'count))) 1
        (if (= (a64_lir_patch_jump context (call_fixup_at jumps index)) 0) 0
            (a64_lir_patch_jumps context (wrap+ index 1))))))

(defun emit_lir_aarch64_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (store (field-pointer jumps 'count) 0)
    (store (field-pointer jumps 'error) 0)
    (if (= (a64_function_prologue (deref (field-pointer context 'code))
                                (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))) 0) 0
        (if (= (a64_lir_emit_instructions context 1) 0) 0 (a64_lir_patch_jumps context 0)))))
