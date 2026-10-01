(include "x86_stack.lisp")

;; x86-64 consumes flat LIR and virtual-register types only. Every virtual
;; register has a frame slot; this baseline keeps calls and joins simple.

(defun x86_lir_load (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (x86_load_local (deref (field-pointer context 'code)) reference
                  (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))))

(defun x86_lir_load_xmm_slot (context register reference)
  (declare (type (ptr native_compile_context) context)
           (type usize register reference) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (disp (x86_local_displacement reference)))
    (if (= (room_for code 8) 0) 0
        (progn
          (emit_byte_unchecked code #xf3)
          (emit_byte_unchecked code #x0f)
          (emit_byte_unchecked code #x7e)
          (emit_byte_unchecked code (wrap-cast u8 (wrap+ #x85 (wrap* register 8))))
          (emit_integer code disp 4)))))

(defun x86_lir_argument_location (code gp fp stack)
  (declare (type u32 code) (type usize gp fp stack) (returns usize))
  (if (= (native_abi_float_p code) 1)
      (if (< fp 8) (native_abi_location 2 fp)
          (native_abi_location 3 stack))
      (if (< gp 6) (native_abi_location 1 gp)
          (native_abi_location 3 stack))))

(defun x86_lir_param_location (context signature index cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize index cursor gp fp stack) (returns usize))
  (let ((code (scalar_signature_parameter_code
               context signature cursor)))
    (if (= cursor index) (x86_lir_argument_location code gp fp stack)
        (let ((location (x86_lir_argument_location code gp fp stack)))
          (x86_lir_param_location context signature index (wrap+ cursor 1)
            (if (= (native_abi_location_class location) 1) (wrap+ gp 1) gp)
            (if (= (native_abi_location_class location) 2) (wrap+ fp 1) fp)
            (if (= (native_abi_location_class location) 3) (wrap+ stack 1) stack))))))

(defun x86_lir_load_abi_parameter (context location)
  (declare (type (ptr native_compile_context) context)
           (type usize location) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (class (native_abi_location_class location))
        (index (native_abi_location_index location)))
    (if (= (room_for code 7) 0) 0
        (progn
          (emit_integer code #x858b48 3)
          (emit_integer code
            (wrap-cast u64
              (if (= class 1) (wrap- 0 (wrap* (wrap+ index 1) 8))
                  (if (= class 2) (wrap- 0 (wrap+ 56 (wrap* index 8)))
                      (wrap+ 16 (wrap* index 8))))) 4)))))

(defun x86_lir_load_argument (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((location (x86_lir_param_location context
                    (deref (field-pointer context 'current_signature))
                    (wrap-cast usize (wrap- (deref (field-pointer op 'value)) 1)) 0 0 0 0)))
    (x86_lir_load_abi_parameter context location)))

(defun x86_lir_normalize (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer op 'scalar_code))))
    (if (= code 12) 1
        (x86_normalize_integer (deref (field-pointer context 'code))
                               (scalar_type_bits code) (scalar_type_signed_p code)))))

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

(defun x86_lir_call_stack_slots (context signature chain remaining largest)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize chain remaining largest) (returns usize))
  (if (= chain 0) largest
      (let ((types (deref (field-pointer (deref (field-pointer context 'lir)) 'types))))
        (let ((link (ir_type_at types chain)))
          (let ((location (x86_lir_param_location context signature
                           (wrap- remaining 1) 0 0 0 0)))
            (x86_lir_call_stack_slots context signature
              (deref (field-pointer link 'right)) (wrap- remaining 1)
              (if (= (native_abi_location_class location) 3)
                  (if (< largest (wrap+ (native_abi_location_index location) 1))
                      (wrap+ (native_abi_location_index location) 1) largest)
                  largest)))))))

(defun x86_lir_move_argument_gp (code index)
  (declare (type (ptr byte_buffer) code) (type usize index) (returns c-int))
  (cond
    ((= index 0) (emit_integer code #xc78948 3))
    ((= index 1) (emit_integer code #xc68948 3))
    ((= index 2) (emit_integer code #xc28948 3))
    ((= index 3) (emit_integer code #xc18948 3))
    ((= index 4) (emit_integer code #xc08949 3))
    ((= index 5) (emit_integer code #xc18949 3))
    (t 0)))

(defun x86_lir_store_stack_argument (code index)
  (declare (type (ptr byte_buffer) code) (type usize index) (returns c-int))
  (if (< 268435450 index) 0
      (if (= (room_for code 8) 0) 0
          (progn
            (emit_integer code #x24848948 4)
            (emit_integer code (wrap-cast u64 (wrap* index 8)) 4)))))

(defun x86_lir_call_arguments (context signature chain remaining)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize chain remaining) (returns c-int))
  (if (= chain 0) 1
      (let ((types (deref (field-pointer (deref (field-pointer context 'lir)) 'types))))
        (let ((link (ir_type_at types chain)))
          (let ((argument (deref (field-pointer link 'left))))
            (let ((location (x86_lir_param_location context signature
                             (wrap- remaining 1) 0 0 0 0))
                    (code (deref (field-pointer context 'code))))
                (let ((class (native_abi_location_class location))
                      (index (native_abi_location_index location)))
                  (if (= class 1)
                      (if (= (x86_lir_load context argument) 0) 0
                          (if (= (x86_lir_move_argument_gp code index) 0) 0
                              (x86_lir_call_arguments context signature
                                (deref (field-pointer link 'right)) (wrap- remaining 1))))
                      (if (= class 2)
                          (if (= (x86_lir_load_xmm_slot context index argument) 0) 0
                              (x86_lir_call_arguments context signature
                                (deref (field-pointer link 'right)) (wrap- remaining 1)))
                          (if (= (x86_lir_load context argument) 0) 0
                              (if (= (x86_lir_store_stack_argument code index) 0) 0
                                  (x86_lir_call_arguments context signature
                                    (deref (field-pointer link 'right))
                                    (wrap- remaining 1)))))))))))))

(defun x86_lir_float_result_to_rax (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (room_for code 5) 0) 0
      (progn
        (emit_byte_unchecked code #x66)
        (emit_byte_unchecked code #x48)
        (emit_byte_unchecked code #x0f)
        (emit_byte_unchecked code #x7e)
        (emit_byte_unchecked code #xc0))))

(defun x86_lir_float_return_from_rax (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (room_for code 5) 0) 0
      (progn
        (emit_byte_unchecked code #x66)
        (emit_byte_unchecked code #x48)
        (emit_byte_unchecked code #x0f)
        (emit_byte_unchecked code #x6e)
        (emit_byte_unchecked code #xc0))))

(defun x86_lir_call_reserved (context op target arity bytes)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op)
           (type usize target arity bytes) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (chain (deref (field-pointer op 'left)))
        (signature (native_signature_at (deref (field-pointer context 'signatures))
                   (wrap- target 1))))
    (if (= (x86_adjust_stack code bytes 1) 0) 0
        (if (= (x86_lir_call_arguments context signature chain arity) 0) 0
            (if (= (emit_deferred_call code (deref (field-pointer context 'fixups)) target 0) 0) 0
                (if (= (x86_adjust_stack code bytes 0) 0) 0
                    (if (= (native_abi_float_p (deref (field-pointer op 'scalar_code))) 1)
                        (if (= (x86_lir_float_result_to_rax code) 0) 0
                            (x86_lir_normalize context op))
                        (x86_lir_normalize context op))))))))

(defun x86_lir_call (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((target (deref (field-pointer op 'target))))
    (let ((function (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1))))
      (store (field-pointer function 'referenced) 1)
      (let ((arity (deref (field-pointer function 'arity))))
        (let ((signature (native_signature_at (deref (field-pointer context 'signatures))
                         (wrap- target 1))))
        (let ((count (x86_lir_call_stack_slots context signature
                       (deref (field-pointer op 'left)) arity 0)))
          ;; Limit the aligned byte reservation to a positive signed imm32.
          (if (< 268435454 count) 0
              (x86_lir_call_reserved context op target arity (x86_stack_argument_bytes count)))))))))

(defun x86_lir_data_address (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((target (deref (field-pointer op 'target)))
        (code (deref (field-pointer context 'code))))
    (if (= target 0) 0
        (if (< (deref (field-pointer context 'data_count)) target) 0
            (let ((start (deref (field-pointer code 'length))))
              (store (field-pointer
                      (native_data_import_at context (wrap- target 1))
                      'referenced) 1)
              (if (= (emit_byte code #x48) 0) 0
                  (if (= (emit_byte code
                                    (if (= (native_target_object_format
                                             (deref (field-pointer context 'target))) 2)
                                        #x8d #x8b)) 0) 0
                      (if (= (emit_byte code #x05) 0) 0
                          (if (= (emit_integer code 0 4) 0) 0
                              (record_call_fixup
                               (deref (field-pointer context 'data_fixups))
                               start target))))))))))

(defun x86_lir_value (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (code (deref (field-pointer context 'code))))
    (cond
      ((= kind 1) (x86_load_immediate code (deref (field-pointer op 'value))))
      ((= kind 19) (x86_load_immediate code (deref (field-pointer op 'value))))
          ((= kind 2)
       (if (= (x86_lir_load_argument context op) 0) 0
           (x86_lir_normalize context op)))
      ((= kind 7) (x86_lir_call context op))
      ((= kind 34) (x86_lir_data_address context op))
      ((= kind 29) 1)
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
       (if (= (deref (field-pointer op 'scalar_code)) 12) (x86_return code)
           (if (= (x86_lir_load context (deref (field-pointer op 'left))) 0) 0
               (if (= (native_abi_float_p (deref (field-pointer op 'scalar_code))) 1)
                   (if (= (x86_lir_float_return_from_rax code) 0) 0 (x86_return code))
                   (x86_return code)))))
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
                  (if (= (x86_lir_store_result context op) 0) 0
                      (x86_lir_emit_instructions context (wrap+ index 1)))))))))

(defun x86_lir_store_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (deref (field-pointer op 'scalar_code)) 12) 1
      (x86_store_local (deref (field-pointer context 'code))
                       (deref (field-pointer op 'destination))
                       (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count)))))

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

(defun x86_lir_prologue (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (x86_function_prologue code
            (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))) 0) 0
        (if (= (native_abi_float_parameters_p context 0) 1)
            (x86_save_float_parameters code 0) 1))))

(defun emit_lir_x86_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((jumps (deref (field-pointer context 'jumps))))
    (store (field-pointer jumps 'count) 0)
    (store (field-pointer jumps 'error) 0)
    (if (= (x86_lir_prologue context) 0) 0
        (if (= (x86_lir_emit_instructions context 1) 0) 0
            (x86_lir_patch_jumps context 0)))))
