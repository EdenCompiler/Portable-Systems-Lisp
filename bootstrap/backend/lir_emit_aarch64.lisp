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

(defun a64_lir_argument_location (scalar_code gp fp stack)
  (declare (type u32 scalar_code) (type usize gp fp stack) (returns usize))
  (if (= (native_abi_float_p scalar_code) 1)
      (if (< fp 8) (native_abi_location 2 fp) (native_abi_location 3 stack))
      (if (< gp 8) (native_abi_location 1 gp) (native_abi_location 3 stack))))

(defun a64_lir_param_location (context signature index cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize index cursor gp fp stack) (returns usize))
  (let ((code (scalar_signature_parameter_code context signature cursor)))
    (if (= cursor index) (a64_lir_argument_location code gp fp stack)
        (let ((location (a64_lir_argument_location code gp fp stack)))
          (a64_lir_param_location context signature index (wrap+ cursor 1)
            (if (= (native_abi_location_class location) 1) (wrap+ gp 1) gp)
            (if (= (native_abi_location_class location) 2) (wrap+ fp 1) fp)
            (if (= (native_abi_location_class location) 3) (wrap+ stack 1) stack))))))

(defun a64_lir_load_abi_parameter (context location)
  (declare (type (ptr native_compile_context) context)
           (type usize location) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (class (native_abi_location_class location))
        (index (native_abi_location_index location)))
    (if (= class 1)
        (a64_load_frame code 9 (wrap* (wrap+ index 1) 8) 1)
        (if (= class 2)
            (a64_load_frame code 9 (wrap+ 72 (wrap* index 8)) 1)
            (a64_load_frame code 9 (wrap+ 16 (wrap* index 8)) 0)))))

(defun a64_lir_argument_next_gp (location gp)
  (declare (type usize location gp) (returns usize))
  (if (= (native_abi_location_class location) 1) (wrap+ gp 1) gp))

(defun a64_lir_argument_next_fp (location fp)
  (declare (type usize location fp) (returns usize))
  (if (= (native_abi_location_class location) 2) (wrap+ fp 1) fp))

(defun a64_lir_argument_next_stack (location stack)
  (declare (type usize location stack) (returns usize))
  (if (= (native_abi_location_class location) 3) (wrap+ stack 1) stack))

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
          ((= kind 18)
           (if (= (native_abi_float_p (deref (field-pointer op 'scalar_code))) 1) 1
               (a64_normalize code 9 (deref (field-pointer op 'scalar_code)))))
          ((= kind 20) (a64_immediate code 9 1))
          ((= kind 23)
           (if (= (a64_immediate code 10 (deref (field-pointer op 'value))) 0) 0
               (a64_register_op code #x8b000000 9 9 10)))
          ((= kind 24) (a64_memory code (wrap-cast usize (deref (field-pointer op 'value)))
                                   (scalar_type_signed_p (deref (field-pointer op 'scalar_code))) 0 9 9))
          (t 1)))))

(defun a64_lir_arguments (context signature chain index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize chain index)
           (returns c-int))
  (if (= index 0) 1
      (let ((types (deref (field-pointer (deref (field-pointer context 'lir)) 'types))))
        (let ((link (ir_type_at types chain)))
          (let ((argument (deref (field-pointer link 'left))))
            (let ((type (ir_type_at types argument)))
              (let ((location (a64_lir_param_location context signature
                               (wrap- index 1) 0 0 0 0))
                    (code (deref (field-pointer context 'code))))
                (if (= (native_abi_location_class location) 1)
                    (if (= (a64_lir_load context (wrap-cast u64 (native_abi_location_index location)) argument) 0) 0
                        (a64_lir_arguments context signature (deref (field-pointer link 'right))
                          (wrap- index 1)))
                    (if (= (native_abi_location_class location) 2)
                        (if (= (a64_lir_load context 9 argument) 0) 0
                            (if (= (a64_general_to_float code
                                      (native_abi_location_index location) 9
                                      (deref (field-pointer type 'scalar_code))) 0) 0
                                (a64_lir_arguments context signature (deref (field-pointer link 'right))
                                  (wrap- index 1))))
                        (if (= (a64_lir_load context 9 argument) 0) 0
                            (if (= (a64_store_stack_argument code 9
                                      (wrap+ 9 (native_abi_location_index location))) 0) 0
                                (a64_lir_arguments context signature (deref (field-pointer link 'right))
                                  (wrap- index 1)))))))))))))

(defun a64_lir_call_stack_count (context signature cursor arity gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize cursor arity gp fp stack) (returns usize))
  (if (= cursor arity) stack
      (let ((code (scalar_signature_parameter_code context signature cursor)))
        (let ((location (a64_lir_argument_location code gp fp stack)))
          (a64_lir_call_stack_count context signature (wrap+ cursor 1) arity
            (a64_lir_argument_next_gp location gp)
            (a64_lir_argument_next_fp location fp)
            (a64_lir_argument_next_stack location stack))))))

(defun a64_lir_call_reserved (context op target arity bytes)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (type usize target arity bytes) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (signature (native_signature_at (deref (field-pointer context 'signatures))
                   (wrap- target 1))))
    (if (= (a64_adjust_stack code bytes 1) 0) (wrap-cast c-int 0)
        (if (= (a64_lir_arguments context signature
                  (deref (field-pointer op 'left)) arity) 0) (wrap-cast c-int 0)
            (if (= (a64_deferred_call code (deref (field-pointer context 'fixups)) target) 0) (wrap-cast c-int 0)
                (if (= (a64_adjust_stack code bytes 0) 0) (wrap-cast c-int 0)
                    (if (= (deref (field-pointer op 'scalar_code)) 12) (wrap-cast c-int 1)
                        (if (= (native_abi_float_p (deref (field-pointer op 'scalar_code))) 1)
                            (a64_float_to_general code 9 0
                              (deref (field-pointer op 'scalar_code)))
                            (if (= (a64_register_op code #xaa000000 9 31 0) 0) (wrap-cast c-int 0)
                                  (a64_normalize code 9
                                  (deref (field-pointer op 'scalar_code))))))))))))

(defun a64_lir_call (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((target (deref (field-pointer op 'target))))
      (let ((function (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1))))
        (let ((arity (deref (field-pointer function 'arity))))
          (if (< 134217719 arity) 0
            (let ((signature (native_signature_at (deref (field-pointer context 'signatures))
                               (wrap- target 1))))
            (let ((stack (a64_lir_call_stack_count context signature 0 arity 0 0 0)))
              (store (field-pointer function 'referenced) 1)
              (a64_lir_call_reserved context op target arity
                (wrap* 8 (bits-and (wrap+ stack 1) (wrap- 0 2)))))))))))

(defun a64_lir_data_address (context op)
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
                  (if (= (a64_word code #x90000009) 0) 0
                      (a64_word code #xf9400129))))))))

(defun a64_lir_value (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op)
           (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 1) (a64_immediate code 9 (deref (field-pointer op 'value))))
      ((= kind 19) (a64_immediate code 9 (deref (field-pointer op 'value))))
      ((= kind 2)
       (let ((location (a64_lir_param_location context
                         (deref (field-pointer context 'current_signature))
                         (wrap-cast usize (wrap- (deref (field-pointer op 'value)) 1)) 0 0 0 0)))
         (if (= (a64_lir_load_abi_parameter context location) 0) 0
             (a64_normalize code 9 (deref (field-pointer op 'scalar_code))))))
      ((= kind 7) (a64_lir_call context op))
      ((= kind 34) (a64_lir_data_address context op))
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
           (if (= (native_abi_float_p (deref (field-pointer op 'scalar_code))) 1)
               (if (= (a64_lir_load context 9 (deref (field-pointer op 'left))) 0) 0
                   (if (= (a64_general_to_float code 0 9
                         (deref (field-pointer op 'scalar_code))) 0) 0 (a64_return code)))
               (if (= (a64_lir_load context 0 (deref (field-pointer op 'left))) 0) 0
                   (a64_return code)))))
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

(defun a64_lir_prologue (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (a64_function_prologue code
            (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))) 0) 0
        (if (= (native_abi_float_parameters_p context 0) 1)
            (a64_save_float_parameters code 0) 1))))

(defun emit_lir_aarch64_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (store (field-pointer jumps 'count) 0)
    (store (field-pointer jumps 'error) 0)
    (if (= (a64_lir_prologue context) 0) 0
        (if (= (a64_lir_emit_instructions context 1) 0) 0 (a64_lir_patch_jumps context 0)))))
