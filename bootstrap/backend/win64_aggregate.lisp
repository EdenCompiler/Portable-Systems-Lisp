;; Microsoft x64 record transport uses exact-byte copies and caller-owned,
;; sixteen-aligned temporary buffers for indirect by-value arguments.
(defun win64_aggregate_indirect_p (context code type)
  (declare (type (ptr native_compile_context) context)
           (type u32 code) (type usize type) (returns c-int))
  (if (= code 16)
      (if (= (native_aggregate_word_size_p (source_type_size context type)) 0) 1 0) 0))

(defun win64_aggregate_hidden (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns usize))
  (if (= (win64_aggregate_indirect_p context (scalar_signature_type_code context signature)
           (scalar_signature_result_pointee context signature)) 1) 1 0))

(defun win64_aggregate_location (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize index) (returns usize))
  (let ((position (wrap+ index (win64_aggregate_hidden context signature)))
        (code (scalar_signature_parameter_code context signature index))
        (type (scalar_signature_parameter_pointee context signature index)))
    (if (= (win64_aggregate_indirect_p context code type) 1)
        (native_abi_location (if (< position 4) (wrap-cast usize 4) (wrap-cast usize 5)) position)
        (win64_lir_argument_location code position))))

(defun win64_aggregate_has_indirect (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize index) (returns c-int))
  (if (= index (deref (field-pointer signature 'arity))) 0
      (if (= (win64_aggregate_indirect_p context
               (scalar_signature_parameter_code context signature index)
               (scalar_signature_parameter_pointee context signature index)) 1) 1
          (win64_aggregate_has_indirect context signature (wrap+ index 1)))))

(defun win64_aggregate_call_base (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns usize))
  (win64_outgoing_bytes (wrap+ (deref (field-pointer signature 'arity))
                               (win64_aggregate_hidden context signature))))

(defun win64_aggregate_outgoing (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns usize))
  (let ((base (win64_aggregate_call_base context signature))
        (count (wrap+ (deref (field-pointer signature 'arity))
                      (win64_aggregate_hidden context signature))))
    (if (= base 0) 0
        (if (= (win64_aggregate_has_indirect context signature 0) 0) base
            (if (< 89478480 count) 0 (wrap+ base (wrap* count 16)))))))

(defun win64_aggregate_storage_base (context outgoing)
  (declare (type (ptr native_compile_context) context) (type usize outgoing) (returns usize))
  (win64_frame_bytes (win64_root_frame_slots context) outgoing))

(defun win64_aggregate_frame (context outgoing)
  (declare (type (ptr native_compile_context) context) (type usize outgoing) (returns usize))
  (let ((base (win64_aggregate_storage_base context outgoing))
        (count (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))))
    (if (= base 0) 0
        (if (= (native_aggregate_sidecars_p context 1) 0) base
            (if (< (shr64 (wrap-cast u64 (wrap- 2147483584 base)) 4) (wrap-cast u64 count)) 0
                (wrap+ base (wrap* count 16)))))))

(defun win64_aggregate_offset (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns usize))
  (wrap+ (win64_aggregate_storage_base context (deref (field-pointer context 'backend_outgoing_size)))
         (wrap* (wrap- reference 1) 16)))

(defun win64_aggregate_address (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns c-int))
  (win64_frame_access (deref (field-pointer context 'code)) #x858d48
                      (win64_aggregate_offset context reference)))

(defun win64_aggregate_copy_bytes (code size index)
  (declare (type (ptr byte_buffer) code) (type usize size index) (returns c-int))
  (if (= size index) 1
      (if (= (room_for code 15) 0) 0
          (progn
            (emit_integer code #x82b60f41 4) ; movzx eax, byte [r10+disp32]
            (emit_integer code (wrap-cast u64 index) 4)
            (emit_integer code #x838841 3) ; mov byte [r11+disp32], al
            (emit_integer code (wrap-cast u64 index) 4)
            (win64_aggregate_copy_bytes code size (wrap+ index 1))))))

(defun win64_aggregate_copy_to_offset (context offset size)
  (declare (type (ptr native_compile_context) context)
           (type usize offset size) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (emit_integer code #xc28949 3) 0) 0 ; r10 = source address in rax
        (if (= (win64_frame_access code #x9d8d4c offset) 0) 0 ; r11 = destination
            (win64_aggregate_copy_bytes code size 0)))))

(defun win64_aggregate_parameter (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (destination (deref (field-pointer op 'destination)))
        (type (deref (field-pointer op 'pointee))))
    (if (= (win64_lir_load_abi_parameter context
              (win64_lir_parameter_location context (wrap-cast usize (deref (field-pointer op 'value))))) 0) 0
        (if (= (if (= (win64_aggregate_indirect_p context 16 type) 1)
                    (win64_aggregate_copy_to_offset context (win64_aggregate_offset context destination)
                                                   (source_type_size context type))
                    (win64_frame_access code #x858948 (win64_aggregate_offset context destination))) 0) 0
            (win64_aggregate_address context destination)))))

(defun win64_aggregate_send (context signature reference index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize reference index) (returns c-int))
  (let ((location (win64_aggregate_location context signature index))
        (code (deref (field-pointer context 'code)))
        (aggregate (native_aggregate_reference_p context reference)))
    (let ((class (native_abi_location_class location))
          (position (native_abi_location_index location)))
      (if (= class 2) (win64_lir_load_xmm_slot context position reference)
          (if (= (win64_lir_load context reference) 0) 0
              (if (= (win64_aggregate_prepare_argument context signature index class position aggregate) 0) 0
                  (if (< position 4) (win64_register_argument code (wrap+ position 1))
                      (win64_stack_argument code (wrap+ position 1)
                        (deref (field-pointer context 'backend_outgoing_size))))))))))

(defun win64_aggregate_prepare_argument (context signature index class position aggregate)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize index class position) (type c-int aggregate) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (if (= class 4) t (= class 5))
        (let ((offset (wrap+ (win64_aggregate_call_base context signature) (wrap* position 16))))
          (if (= (win64_aggregate_copy_to_offset context offset
                   (source_type_size context (scalar_signature_parameter_pointee context signature index))) 0) 0
              (win64_frame_access code #x858d48 offset)))
        (if (= aggregate 1) (emit_integer code #x008b48 3) 1))))

(defun win64_aggregate_call_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (if (= (win64_aggregate_indirect_p context 16 (deref (field-pointer op 'pointee))) 1)
      (win64_aggregate_address context (deref (field-pointer op 'destination)))
      (if (= (win64_frame_access (deref (field-pointer context 'code)) #x858948
               (win64_aggregate_offset context (deref (field-pointer op 'destination)))) 0) 0
          (win64_aggregate_address context (deref (field-pointer op 'destination))))))

(defun win64_aggregate_hidden_argument (context signature destination)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize destination) (returns c-int))
  (if (= (win64_aggregate_hidden context signature) 0) 1
      (if (= (win64_aggregate_address context destination) 0) 0
          (win64_register_argument (deref (field-pointer context 'code)) 1))))

(defun win64_aggregate_return (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (frame (deref (field-pointer context 'backend_frame_size))))
    (if (= (win64_lir_load context (deref (field-pointer op 'left))) 0) 0
        (if (= (win64_aggregate_indirect_p context 16 (deref (field-pointer op 'pointee))) 0)
            (if (= (emit_integer code #x008b48 3) 0) 0 (win64_return code frame))
            (if (= (emit_integer code #xc28949 3) 0) 0 ; r10 = private source
                (if (= (win64_load_parameter code (deref (field-pointer context 'backend_outgoing_size)) frame 1) 0) 0
                    (if (= (emit_integer code #xc38949 3) 0) 0 ; r11 = caller result pointer
                        (if (= (win64_aggregate_copy_bytes code
                                 (source_type_size context (deref (field-pointer op 'pointee))) 0) 0) 0
                            (if (= (win64_load_parameter code (deref (field-pointer context 'backend_outgoing_size)) frame 1) 0) 0
                                (win64_return code frame))))))))))
