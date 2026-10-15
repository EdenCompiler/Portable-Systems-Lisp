;; SysV INTEGER aggregate pieces use the existing GP and stack ABI locations.
;; Large record virtual words point to private immutable frame storage.

(defun x86_aggregate_parameter_words (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize index) (returns usize))
  (native_aggregate_parameter_words context signature index))

(defun x86_aggregate_location (context signature cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize cursor gp fp stack) (returns usize))
  (if (= (x86_aggregate_parameter_words context signature cursor) 2)
      (if (< gp 5) (native_abi_location 1 gp) (native_abi_location 3 stack))
      (x86_lir_argument_location (scalar_signature_parameter_code context signature cursor) gp fp stack)))

(defun x86_aggregate_displacement (context reference part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference part) (returns u64))
  (wrap+ (x86_local_displacement (wrap+ (native_root_frame_slots context) (wrap* reference 2)))
         (wrap-cast u64 (wrap* part 8))))

(defun x86_aggregate_frame_op (context opcode reference part)
  (declare (type (ptr native_compile_context) context)
           (type u64 opcode) (type usize reference part) (returns c-int))
  (x86_root_memory (deref (field-pointer context 'code)) opcode
                   (x86_aggregate_displacement context reference part)))

(defun x86_aggregate_address (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns c-int))
  (x86_aggregate_frame_op context #x858d48 reference 0))

(defun x86_aggregate_incoming_parts (context destination location part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination location part words) (returns c-int))
  (if (= part words) (x86_aggregate_address context destination)
      (if (= (x86_lir_load_abi_parameter context
               (native_abi_location (native_abi_location_class location)
                 (wrap+ (native_abi_location_index location) part))) 0) 0
          (if (= (x86_aggregate_frame_op context #x858948 destination part) 0) 0
              (x86_aggregate_incoming_parts context destination location (wrap+ part 1) words)))))

(defun x86_aggregate_load_part (context reference part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference part) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (x86_lir_load context reference) 0) 0
        (if (= (room_for code 10) 0) 0
            (progn
              (emit_integer code #xc28949 3) ; mov r10, rax
              (emit_integer code #x828b49 3) ; mov rax, [r10+disp32]
              (emit_integer code (wrap-cast u64 (wrap* part 8)) 4))))))

(defun x86_aggregate_send_part (context location reference words part)
  (declare (type (ptr native_compile_context) context)
           (type usize location reference words part) (returns c-int))
  (if (= part words) 1
      (let ((code (deref (field-pointer context 'code)))
            (class (native_abi_location_class location))
            (index (wrap+ (native_abi_location_index location) part)))
        (if (= class 2)
            (x86_lir_load_xmm_slot context index reference)
            (if (= (if (= (native_aggregate_reference_p context reference) 1) (x86_aggregate_load_part context reference part)
                       (x86_lir_load context reference)) 0) 0
                (if (= (if (= class 1) (x86_lir_move_argument_gp code index)
                           (x86_lir_store_stack_argument code index)) 0) 0
                    (x86_aggregate_send_part context location reference words (wrap+ part 1))))))))

(defun x86_aggregate_call_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((destination (deref (field-pointer op 'destination))))
    (if (= (x86_aggregate_frame_op context #x858948 destination 0) 0) 0
        (if (= (if (= (native_aggregate_words context 16 (deref (field-pointer op 'pointee))) 2)
                   (x86_aggregate_frame_op context #x958948 destination 1) (wrap-cast c-int 1)) 0) 0
            (x86_aggregate_address context destination)))))

(defun x86_aggregate_return (context reference words)
  (declare (type (ptr native_compile_context) context) (type usize reference words) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (x86_lir_load context reference) 0) 0
        (if (= (room_for code 15) 0) 0
            (progn
              (emit_integer code #xc28949 3) ; mov r10, rax
              (if (= words 2)
                  (progn (emit_integer code #x928b49 3) ; mov rdx, [r10+8]
                         (emit_integer code 8 4)) (wrap-cast c-int 1))
              (emit_integer code #x028b49 3) ; mov rax, [r10]
              (x86_return code))))))
