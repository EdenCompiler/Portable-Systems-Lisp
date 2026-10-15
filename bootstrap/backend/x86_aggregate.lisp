;; SysV INTEGER aggregate pieces use the existing GP and stack ABI locations.
;; Large record virtual words point to private immutable frame storage.

(defun x86_aggregate_parameter_words (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize index) (returns usize))
  (native_aggregate_parameter_words context signature index))

(defun x86_aggregate_class_scan (context type part index found)
  (declare (type (ptr native_compile_context) context)
           (type usize type part index found) (returns usize))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) (if (= found 0) 1 found)
        (if (= (shr64 (wrap-cast u64 (native_aggregate_leaf_offset leaf)) 3)
               (wrap-cast u64 part))
            (if (= (native_abi_float_p (native_aggregate_leaf_code leaf)) 0) 1
                (x86_aggregate_class_scan context type part (wrap+ index 1) 2))
            (x86_aggregate_class_scan context type part (wrap+ index 1) found)))))

(defun x86_aggregate_class (context type part)
  (declare (type (ptr native_compile_context) context)
           (type usize type part) (returns usize))
  (x86_aggregate_class_scan context type part 0 0))

(defun x86_aggregate_class_count (context type class part words)
  (declare (type (ptr native_compile_context) context)
           (type usize type class part words) (returns usize))
  (if (= part words) 0
      (wrap+ (if (= (x86_aggregate_class context type part) class)
                 (wrap-cast usize 1) (wrap-cast usize 0))
             (x86_aggregate_class_count context type class (wrap+ part 1) words))))

(defun x86_aggregate_location (context signature cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize cursor gp fp stack) (returns usize))
  (let ((code (scalar_signature_parameter_code context signature cursor))
        (type (scalar_signature_parameter_pointee context signature cursor)))
    (if (= code 16)
        (let ((words (native_aggregate_words context code type)))
          (if (if (< 6 (wrap+ gp (x86_aggregate_class_count context type 1 0 words))) t
                  (< 8 (wrap+ fp (x86_aggregate_class_count context type 2 0 words))))
              (native_abi_location 3 stack)
              (native_abi_location 4 (wrap+ gp (wrap* fp 16)))))
        (x86_lir_argument_location code gp fp stack))))

(defun x86_aggregate_next_register (context signature cursor location count class)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize cursor location count class) (returns usize))
  (if (= (native_abi_location_class location) 4)
      (let ((type (scalar_signature_parameter_pointee context signature cursor)))
        (wrap+ count (x86_aggregate_class_count context type class 0
                       (native_aggregate_words context 16 type))))
      (if (= (native_abi_location_class location) class) (wrap+ count 1) count)))

(defun x86_aggregate_part_location (context type location part)
  (declare (type (ptr native_compile_context) context)
           (type usize type location part) (returns usize))
  (let ((index (native_abi_location_index location)))
    (if (= (native_abi_location_class location) 4)
        (let ((class (x86_aggregate_class context type part)))
          (native_abi_location class
            (wrap+ (if (= class 1) (bits-and index 15)
                       (wrap-cast usize (shr64 (wrap-cast u64 index) 4)))
                   (x86_aggregate_class_count context type class 0 part))))
        (native_abi_location (native_abi_location_class location) (wrap+ index part)))))

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

(defun x86_aggregate_incoming_parts (context destination type location part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination type location part words) (returns c-int))
  (if (= part words) (x86_aggregate_address context destination)
      (if (= (x86_lir_load_abi_parameter context
               (x86_aggregate_part_location context type location part)) 0) 0
          (if (= (x86_aggregate_frame_op context #x858948 destination part) 0) 0
              (x86_aggregate_incoming_parts context destination type location (wrap+ part 1) words)))))

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

(defun x86_aggregate_move_xmm (code index)
  (declare (type (ptr byte_buffer) code) (type usize index) (returns c-int))
  (if (= (emit_integer code #x6e0f4866 4) 0) 0
      (emit_integer code (wrap-cast u64 (wrap+ #xc0 (wrap* index 8))) 1)))

(defun x86_aggregate_send_piece (context reference type location part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference type location part) (returns c-int))
  (let ((destination (x86_aggregate_part_location context type location part))
        (code (deref (field-pointer context 'code))))
    (if (= (x86_aggregate_load_part context reference part) 0) 0
        (let ((class (native_abi_location_class destination))
              (index (native_abi_location_index destination)))
          (cond
            ((= class 1) (x86_lir_move_argument_gp code index))
            ((= class 2) (x86_aggregate_move_xmm code index))
            (t (x86_lir_store_stack_argument code index)))))))

(defun x86_aggregate_send_part (context location reference words part)
  (declare (type (ptr native_compile_context) context)
           (type usize location reference words part) (returns c-int))
  (if (= part words) 1
      (if (= (native_aggregate_reference_p context reference) 1)
          (let ((type (deref (field-pointer (ir_type_at
                         (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) reference) 'pointee))))
            (if (= (x86_aggregate_send_piece context reference type location part) 0) 0
                (x86_aggregate_send_part context location reference words (wrap+ part 1))))
          (if (= (native_abi_location_class location) 2)
              (x86_lir_load_xmm_slot context (native_abi_location_index location) reference)
              (if (= (x86_lir_load context reference) 0) 0
                  (if (= (native_abi_location_class location) 1)
                      (x86_lir_move_argument_gp (deref (field-pointer context 'code))
                        (native_abi_location_index location))
                      (x86_lir_store_stack_argument (deref (field-pointer context 'code))
                        (native_abi_location_index location))))))))

(defun x86_aggregate_receive_result (context destination type part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination type part words) (returns c-int))
  (if (= part words) (x86_aggregate_address context destination)
      (let ((class (x86_aggregate_class context type part))
            (code (deref (field-pointer context 'code))))
        (let ((index (x86_aggregate_class_count context type class 0 part)))
          (if (= (if (= class 1)
                      (x86_aggregate_frame_op context (if (= index 0) #x858948 #x958948) destination part)
                      (if (= (emit_integer code #xd60f66 3) 0) (wrap-cast c-int 0)
                          (if (= (emit_integer code (wrap-cast u64 (wrap+ #x85 (wrap* index 8))) 1) 0) (wrap-cast c-int 0)
                              (wrap-cast c-int (emit_integer code (x86_aggregate_displacement context destination part) 4))))) 0) 0
              (x86_aggregate_receive_result context destination type (wrap+ part 1) words))))))

(defun x86_aggregate_call_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((type (deref (field-pointer op 'pointee))))
    (x86_aggregate_receive_result context (deref (field-pointer op 'destination)) type 0
      (native_aggregate_words context 16 type))))

(defun x86_aggregate_return_piece (context type part)
  (declare (type (ptr native_compile_context) context)
           (type usize type part) (returns c-int))
  (let ((class (x86_aggregate_class context type part))
        (code (deref (field-pointer context 'code))))
    (let ((index (x86_aggregate_class_count context type class 0 part)))
      (if (= (if (= class 1)
                  (emit_integer code (if (= index 0) #x828b49 #x928b49) 3)
                  (if (= (emit_integer code #x7e0f41f3 4) 0) (wrap-cast c-int 0)
                      (emit_integer code (wrap-cast u64 (wrap+ #x82 (wrap* index 8))) 1))) 0) 0
          (emit_integer code (wrap-cast u64 (wrap* part 8)) 4)))))

(defun x86_aggregate_return_parts (context type part words)
  (declare (type (ptr native_compile_context) context)
           (type usize type part words) (returns c-int))
  (if (= part words) (x86_return (deref (field-pointer context 'code)))
      (if (= (x86_aggregate_return_piece context type part) 0) 0
          (x86_aggregate_return_parts context type (wrap+ part 1) words))))

(defun x86_aggregate_return (context reference words)
  (declare (type (ptr native_compile_context) context) (type usize reference words) (returns c-int))
  (let ((type (deref (field-pointer (ir_type_at
                   (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) reference) 'pointee))))
    (if (= (x86_lir_load context reference) 0) 0
        (if (= (emit_integer (deref (field-pointer context 'code)) #xc28949 3) 0) 0
            (x86_aggregate_return_parts context type 0 words)))))
