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
          ((= kind 18) (if (= (native_abi_float_p (deref (field-pointer op 'scalar_code))) 1) 1
                           (rv_normalize code 5 (deref (field-pointer op 'scalar_code)))))
          ((= kind 20) (rv_immediate code 5 1))
          ((= kind 23)
           (if (= (rv_immediate code 6 (deref (field-pointer op 'value))) 0) 0
               (rv_r code #x33 5 5 6 0 0)))
          ((= kind 24) (rv_load_memory code (wrap-cast usize (deref (field-pointer op 'value)))
                                         (deref (field-pointer op 'scalar_code))))
          (t 1)))))

(defun rv_lir_argument_location (scalar_code gp fp stack)
  (declare (type u32 scalar_code) (type usize gp fp stack) (returns usize))
  (if (= (native_abi_float_p scalar_code) 1)
      (if (< fp 8) (native_abi_location 2 fp)
          (if (< gp 8) (native_abi_location 1 gp) (native_abi_location 3 stack)))
      (if (< gp 8) (native_abi_location 1 gp) (native_abi_location 3 stack))))

(defun rv_lir_param_location (context signature index cursor gp fp stack)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (type usize index cursor gp fp stack) (returns usize))
  (let ((scalar_code (scalar_signature_parameter_code context signature cursor)))
    (let ((location (rv_lir_argument_location scalar_code gp fp stack)))
      (if (= cursor index) location
          (rv_lir_param_location context signature index (wrap+ cursor 1)
            (if (= (native_abi_location_class location) 1) (wrap+ gp 1) gp)
            (if (= (native_abi_location_class location) 2) (wrap+ fp 1) fp)
            (if (= (native_abi_location_class location) 3) (wrap+ stack 1) stack))))))

(defun rv_lir_load_abi_parameter (context location)
  (declare (type (ptr native_compile_context) context) (type usize location) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (class (native_abi_location_class location)) (index (native_abi_location_index location)))
    (if (= class 1) (rv_load_frame code 5 (wrap+ 24 (wrap* index 8)) 1)
        (if (= class 2) (rv_load_frame code 5 (wrap+ 88 (wrap* index 8)) 1)
            (rv_load_frame code 5 (wrap* index 8) 0)))))

(defun rv_lir_next_gp (location gp) (declare (type usize location gp) (returns usize))
  (if (= (native_abi_location_class location) 1) (wrap+ gp 1) gp))
(defun rv_lir_next_fp (location fp) (declare (type usize location fp) (returns usize))
  (if (= (native_abi_location_class location) 2) (wrap+ fp 1) fp))
(defun rv_lir_next_stack (location stack) (declare (type usize location stack) (returns usize))
  (if (= (native_abi_location_class location) 3) (wrap+ stack 1) stack))

(defun rv_lir_normalize_argument (code register scalar_code)
  (declare (type (ptr byte_buffer) code) (type u64 register)
           (type u32 scalar_code) (returns c-int))
  (if (= (native_abi_float_p scalar_code) 1) 1
      (rv_abi_normalize code register scalar_code)))

(defun rv_lir_send_argument (context location reference scalar_code)
  (declare (type (ptr native_compile_context) context)
           (type usize location reference) (type u32 scalar_code) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (class (native_abi_location_class location))
        (index (native_abi_location_index location)))
    (cond
      ((= class 1)
       (let ((register (wrap-cast u64 (wrap+ 10 index))))
         (if (= (rv_lir_load context register reference) 0) 0
             (rv_lir_normalize_argument code register scalar_code))))
      ((= class 2)
       (if (= (rv_lir_load context 5 reference) 0) 0
           (rv_general_to_float code (wrap+ 10 index) 5 scalar_code)))
      (t (if (= (rv_lir_load context 5 reference) 0) 0
             (if (= (rv_lir_normalize_argument code 5 scalar_code) 0) 0
                 (rv_store_stack_argument code 5 (wrap+ 9 index))))))))

(defun rv_lir_arguments (context signature chain index)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (type usize chain index) (returns c-int))
  (if (= index 0) 1
      (let ((types (deref (field-pointer (deref (field-pointer context 'lir)) 'types))))
        (let ((link (ir_type_at types chain)))
          (let ((reference (deref (field-pointer link 'left)))
                (location (rv_lir_param_location context signature (wrap- index 1) 0 0 0 0)))
            (if (= (rv_lir_send_argument context location reference
                     (deref (field-pointer (ir_type_at types reference) 'scalar_code))) 0) 0
                (rv_lir_arguments context signature (deref (field-pointer link 'right))
                                   (wrap- index 1))))))))

(defun rv_lir_stack_count (context signature cursor arity gp fp stack)
  (declare (type (ptr native_compile_context) context) (type (ptr native_signature) signature)
           (type usize cursor arity gp fp stack) (returns usize))
  (if (= cursor arity) stack
      (let ((location (rv_lir_argument_location (scalar_signature_parameter_code context signature cursor) gp fp stack)))
        (rv_lir_stack_count context signature (wrap+ cursor 1) arity
          (rv_lir_next_gp location gp) (rv_lir_next_fp location fp) (rv_lir_next_stack location stack)))))

(defun rv_lir_call_reserved (context op target arity bytes)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (type usize target arity bytes) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (signature (native_signature_at (deref (field-pointer context 'signatures)) (wrap- target 1))))
    (if (= (rv_adjust_stack code bytes 1) 0) 0
        (if (= (rv_lir_arguments context signature (deref (field-pointer op 'left)) arity) 0) 0
            (if (= (rv_deferred_call code (deref (field-pointer context 'fixups)) target) 0) 0
                (if (= (rv_adjust_stack code bytes 0) 0) 0
                    (if (= (deref (field-pointer op 'scalar_code)) 12) 1
                        (if (= (native_abi_float_p (deref (field-pointer op 'scalar_code))) 1)
                            (if (= (rv_float_to_general code 5 10 (deref (field-pointer op 'scalar_code))) 0) 0
                                (rv_normalize code 5 (deref (field-pointer op 'scalar_code))))
                            (if (= (rv_move code 5 10) 0) 0
                                (rv_normalize code 5 (deref (field-pointer op 'scalar_code))))))))))))

(defun rv_lir_call (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((target (deref (field-pointer op 'target))))
    (let ((function (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1))))
      (let ((arity (deref (field-pointer function 'arity))))
        (if (< 134217719 arity) 0
            (progn
              (store (field-pointer function 'referenced) 1)
              (let ((signature (native_signature_at (deref (field-pointer context 'signatures)) (wrap- target 1))))
                (let ((stack (rv_lir_stack_count context signature 0 arity 0 0 0)))
                  (rv_lir_call_reserved context op target arity
                    (wrap* 8 (bits-and (wrap+ stack 1) (wrap- 0 2))))))))))))

(defun rv_lir_data_address (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((target (deref (field-pointer op 'target)))
        (code (deref (field-pointer context 'code))))
    (if (= target 0) 0
        (if (< (deref (field-pointer context 'data_count)) target) 0
            (progn
              (store (field-pointer
                      (native_data_import_at context (wrap- target 1))
                      'referenced) 1)
              (if (= (record_call_fixup
                      (deref (field-pointer context 'data_fixups))
                      (deref (field-pointer code 'length)) target) 0) 0
                  (if (= (rv_word code #x00000297) 0) 0
                      (rv_i code #x03 5 5 3 0))))))))

(defun rv_lir_value (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 1) (rv_immediate code 5 (deref (field-pointer op 'value))))
      ((= kind 19) (rv_immediate code 5 (deref (field-pointer op 'value))))
      ((= kind 2)
       (let ((location (rv_lir_param_location context (deref (field-pointer context 'current_signature))
                         (wrap-cast usize (wrap- (deref (field-pointer op 'value)) 1)) 0 0 0 0)))
         (if (= (rv_lir_load_abi_parameter context location) 0) 0
             (rv_normalize code 5 (deref (field-pointer op 'scalar_code))))))
      ((= kind 7) (rv_lir_call context op))
      ((= kind 34) (rv_lir_data_address context op))
      ((= kind 29) 1)
      ((= (ir_binary_kind_p kind) 1) (rv_lir_binary context op))
      (t (rv_lir_unary context op)))))

(defun rv_lir_jump (context target)
  (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (record_call_fixup (deref (field-pointer context 'jumps))
                              (deref (field-pointer code 'length)) target) 0) 0
        (rv_reserve_pair code 7 0))))

(defun rv_lir_return_value (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (scalar_code (deref (field-pointer op 'scalar_code))))
    (if (= scalar_code 12) (rv_return code)
        (if (= (rv_lir_load context 10 (deref (field-pointer op 'left))) 0) 0
            (if (= (if (= (native_abi_float_p scalar_code) 1)
                       (rv_general_to_float code 10 10 scalar_code)
                       (rv_abi_normalize code 10 scalar_code)) 0) 0
                (rv_return code))))))

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
           (if (= (rv_word code #x00029663) 0) 0
               (if (= (rv_lir_jump context (deref (field-pointer op 'right))) 0) 0
                   (rv_lir_jump context (deref (field-pointer op 'target)))))))
      ((= kind 103) (rv_lir_return_value context op))
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

(defun rv_lir_prologue (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (rv_function_prologue code
            (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))) 0) 0
        (if (= (native_abi_float_parameters_p context 0) 1)
            (rv_save_float_parameters code 0) 1))))

(defun emit_lir_riscv64_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (store (field-pointer jumps 'count) 0)
    (store (field-pointer jumps 'error) 0)
    (if (= (rv_lir_prologue context) 0) 0
        (if (= (rv_lir_emit_instructions context 1) 0) 0 (rv_lir_patch_jumps context 0)))))
