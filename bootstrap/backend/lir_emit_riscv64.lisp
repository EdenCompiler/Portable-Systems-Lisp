(include "riscv64_frame.lisp")
(include "riscv64_branches.lisp")
(include "riscv64_memory.lisp")

(defun rv_lir_load (context register reference)
  (declare (type (ptr native_compile_context) context) (type u64 register)
           (type usize reference) (returns c-int))
  (rv_load_frame (deref (field-pointer context 'code)) register (rv_local_offset reference) 1))

(defun rv_lir_compare (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((type (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types))
                         (deref (field-pointer op 'left))))
        (code (deref (field-pointer context 'code))))
    (if (= (deref (field-pointer op 'kind)) 8)
        (if (= (rv_r code #x33 5 5 6 4 0) 0) 0 (rv_i code #x13 5 5 3 1))
        (rv_r code #x33 5 5 6
          (if (= (scalar_type_signed_p (deref (field-pointer type 'scalar_code))) 1) 2 (wrap-cast u64 3)) 0))))

(defun rv_lir_arithmetic (code kind scalar_code)
  (declare (type (ptr byte_buffer) code) (type u32 kind scalar_code) (returns c-int))
  (let ((funct3 (if (= kind 11) (wrap-cast u64 7)
                   (if (= kind 12) (wrap-cast u64 5) (wrap-cast u64 0))))
        (funct7 (if (= kind 5) (wrap-cast u64 32)
                   (if (= kind 6) (wrap-cast u64 1) (wrap-cast u64 0)))))
    (if (= (rv_r code #x33 5 5 6 funct3 funct7) 0) 0
        (rv_normalize code 5 scalar_code))))

(defun rv_lir_pointer_add (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (rv_immediate code 28 (deref (field-pointer op 'value))) 0) 0
        (if (= (rv_r code #x33 6 6 28 0 1) 0) 0 (rv_r code #x33 5 5 6 0 0)))))

(defun rv_lir_store (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (rv_store_bytes (deref (field-pointer context 'code))
                 (wrap-cast usize (deref (field-pointer op 'value))) 0))

(defun rv_lir_binary (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (if (= (rv_lir_load context 5 (deref (field-pointer op 'left))) 0) 0
      (if (= (rv_lir_load context 6 (deref (field-pointer op 'right))) 0) 0
          (let ((kind (deref (field-pointer op 'kind)))
                (code (deref (field-pointer context 'code))))
            (cond
              ((= kind 8) (rv_lir_compare context op))
              ((= kind 9) (rv_lir_compare context op))
              ((= kind 25) (rv_lir_store context op))
              ((= kind 27) (rv_lir_pointer_add context op))
              (t (rv_lir_arithmetic code kind (deref (field-pointer op 'scalar_code)))))))))

(defun rv_lir_unary (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (if (= (rv_lir_load context 5 (deref (field-pointer op 'left))) 0) 0
      (let ((code (deref (field-pointer context 'code)))
            (kind (deref (field-pointer op 'kind))))
        (cond
          ((= kind 18) (rv_normalize code 5 (deref (field-pointer op 'scalar_code))))
          ((= kind 20) (rv_immediate code 5 1))
          ((= kind 23)
           (if (= (rv_immediate code 6 (deref (field-pointer op 'value))) 0) 0
               (rv_r code #x33 5 5 6 0 0)))
          ((= kind 24) (rv_load_memory code (wrap-cast usize (deref (field-pointer op 'value)))
                                         (deref (field-pointer op 'scalar_code))))
          (t 1)))))

(defun rv_lir_argument (context reference index)
  (declare (type (ptr native_compile_context) context) (type usize reference index) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (type (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) reference)))
    (let ((register (if (< 8 index) (wrap-cast u64 5) (wrap-cast u64 (wrap+ 9 index)))))
      (if (= (rv_lir_load context register reference) 0) 0
          (if (= (rv_abi_normalize code register (deref (field-pointer type 'scalar_code))) 0) 0
              (if (< 8 index) (rv_store_stack_argument code register index) 1))))))

(defun rv_lir_arguments (context chain index)
  (declare (type (ptr native_compile_context) context) (type usize chain index) (returns c-int))
  (if (= index 0) 1
      (let ((link (ir_type_at (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) chain)))
        (if (= (rv_lir_argument context (deref (field-pointer link 'left)) index) 0) 0
            (rv_lir_arguments context (deref (field-pointer link 'right)) (wrap- index 1))))))

(defun rv_lir_call_reserved (context op target arity bytes)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (type usize target arity bytes) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (rv_adjust_stack code bytes 1) 0) 0
        (if (= (rv_lir_arguments context (deref (field-pointer op 'left)) arity) 0) 0
            (if (= (rv_deferred_call code (deref (field-pointer context 'fixups)) target) 0) 0
                (if (= (rv_adjust_stack code bytes 0) 0) 0
                    (if (= (deref (field-pointer op 'scalar_code)) 12) 1
                        (if (= (rv_move code 5 10) 0) 0
                            (rv_normalize code 5 (deref (field-pointer op 'scalar_code)))))))))))

(defun rv_lir_call (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((target (deref (field-pointer op 'target))))
    (let ((function (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1))))
      (let ((arity (deref (field-pointer function 'arity))))
        (if (< 134217719 arity) 0
            (progn
              (store (field-pointer function 'referenced) 1)
              (rv_lir_call_reserved context op target arity
                (if (< 8 arity) (wrap* 8 (bits-and (wrap- arity 7) (wrap- 0 2)))
                    (wrap-cast usize 0)))))))))

(defun rv_lir_value (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 1) (rv_immediate code 5 (deref (field-pointer op 'value))))
      ((= kind 19) (rv_immediate code 5 (deref (field-pointer op 'value))))
      ((= kind 2)
       (if (= (rv_load_parameter code 5 (wrap-cast usize (deref (field-pointer op 'value)))) 0) 0
           (rv_normalize code 5 (deref (field-pointer op 'scalar_code)))))
      ((= kind 7) (rv_lir_call context op))
      ((= kind 29) 1)
      ((= (ir_binary_kind_p kind) 1) (rv_lir_binary context op))
      (t (rv_lir_unary context op)))))

(defun rv_lir_jump (context target)
  (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (record_call_fixup (deref (field-pointer context 'jumps))
                              (deref (field-pointer code 'length)) target) 0) 0
        (rv_reserve_pair code 7 0))))

(defun rv_lir_control (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 100)
       (store (pointer+ (deref (field-pointer context 'labels))
                        (wrap-cast isize (wrap- (deref (field-pointer op 'target)) 1)))
              (deref (field-pointer code 'length))) 1)
      ((= kind 101) (rv_lir_jump context (deref (field-pointer op 'target))))
      ((= kind 102)
       (if (= (rv_lir_load context 5 (deref (field-pointer op 'left))) 0) 0
           (if (= (rv_word code #x00029663) 0) 0 ; bne t0, zero, +12
               (if (= (rv_lir_jump context (deref (field-pointer op 'right))) 0) 0
                   (rv_lir_jump context (deref (field-pointer op 'target)))))))
      ((= kind 103)
       (if (= (deref (field-pointer op 'scalar_code)) 12) (rv_return code)
           (if (= (rv_lir_load context 10 (deref (field-pointer op 'left))) 0) 0
               (if (= (rv_abi_normalize code 10 (deref (field-pointer op 'scalar_code))) 0) 0
                   (rv_return code)))))
      (t 0))))

(defun rv_lir_store_result (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (if (= (deref (field-pointer op 'scalar_code)) 12) 1
      (rv_store_frame (deref (field-pointer context 'code)) 5
                       (rv_local_offset (deref (field-pointer op 'destination))))))

(defun rv_lir_emit_instructions (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((lir (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer lir 'count)) index) 1
        (let ((op (lir_instruction_at lir index)))
          (if (= (deref (field-pointer op 'destination)) 0)
              (if (= (rv_lir_control context op) 0) 0 (rv_lir_emit_instructions context (wrap+ index 1)))
              (if (= (rv_lir_value context op) 0) 0
                  (if (= (rv_lir_store_result context op) 0) 0
                      (rv_lir_emit_instructions context (wrap+ index 1)))))))))

(defun rv_lir_patch_jump (context fixup)
  (declare (type (ptr native_compile_context) context) (type (ptr native_call_fixup) fixup)
           (returns c-int))
  (let ((destination (deref (pointer+ (deref (field-pointer context 'labels))
                         (wrap-cast isize (wrap- (deref (field-pointer fixup 'target)) 1))))))
    (rv_patch_pair (deref (field-pointer context 'code))
                    (deref (field-pointer fixup 'instruction)) destination 7 0)))

(defun rv_lir_patch_jumps (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (if (= index (deref (field-pointer jumps 'count))) 1
        (if (= (rv_lir_patch_jump context (call_fixup_at jumps index)) 0) 0
            (rv_lir_patch_jumps context (wrap+ index 1))))))

(defun emit_lir_riscv64_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (store (field-pointer jumps 'count) 0)
    (store (field-pointer jumps 'error) 0)
    (if (= (rv_function_prologue (deref (field-pointer context 'code))
                                (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))) 0) 0
        (if (= (rv_lir_emit_instructions context 1) 0) 0 (rv_lir_patch_jumps context 0)))))
