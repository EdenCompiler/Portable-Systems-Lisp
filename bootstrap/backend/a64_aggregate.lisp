;; AAPCS64 integer aggregate locations and immutable private frame copies.
(defun a64_aggregate_location (context signature cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize cursor gp fp stack) (returns usize))
  (let ((code (scalar_signature_parameter_code context signature cursor))
        (type (scalar_signature_parameter_pointee context signature cursor)))
    (if (= code 16)
        (if (< 0 (native_aggregate_hfa_code context type))
            (if (< 8 (wrap+ fp (native_aggregate_leaf_count context type)))
                (native_abi_location 5 stack) (native_abi_location 4 fp))
            (if (= (native_aggregate_words context code type) 2)
                (if (< gp 7) (native_abi_location 1 gp) (native_abi_location 3 stack))
                (a64_lir_argument_location code gp fp stack)))
        (a64_lir_argument_location code gp fp stack))))

(defun a64_aggregate_next_fp (context signature cursor location fp)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize cursor location fp) (returns usize))
  (let ((class (native_abi_location_class location)))
    (if (= class 4)
        (wrap+ fp (native_aggregate_leaf_count context
                    (scalar_signature_parameter_pointee context signature cursor)))
        (if (= class 5) 8 (a64_lir_argument_next_fp location fp)))))

(defun a64_aggregate_next_gp (location words gp)
  (declare (type usize location words gp) (returns usize))
  (if (= (native_abi_location_class location) 1) (wrap+ gp words)
      (if (if (= (native_abi_location_class location) 3) (= words 2) nil) 8 gp)))

(defun a64_aggregate_next_stack (location words stack)
  (declare (type usize location words stack) (returns usize))
  (if (if (= (native_abi_location_class location) 3) t
          (= (native_abi_location_class location) 5)) (wrap+ stack words) stack))

(defun a64_aggregate_offset (context reference part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference part) (returns usize))
  (wrap- (a64_local_offset (wrap+ (native_root_frame_slots context) (wrap* reference 2)))
         (wrap* part 8)))

(defun a64_aggregate_address (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns c-int))
  (a64_root_address context 9 (a64_aggregate_offset context reference 0)))

(defun a64_aggregate_incoming_words (context destination location part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination location part words) (returns c-int))
  (if (= part words) (a64_aggregate_address context destination)
      (if (= (a64_lir_load_abi_parameter context
               (native_abi_location (native_abi_location_class location)
                 (wrap+ (native_abi_location_index location) part))) 0) 0
          (if (= (a64_store_frame (deref (field-pointer context 'code)) 9
                   (a64_aggregate_offset context destination part)) 0) 0
              (a64_aggregate_incoming_words context destination location (wrap+ part 1) words)))))

(defun a64_aggregate_load_part (context reference part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference part) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (a64_lir_load context 9 reference) 0) 0
        (if (= (a64_immediate code 10 (wrap-cast u64 (wrap* part 8))) 0) 0
            (if (= (a64_register_op code #x8b000000 9 9 10) 0) 0
                (a64_memory code 8 0 0 9 9))))))

(defun a64_aggregate_send_words (context reference scalar_code location words part)
  (declare (type (ptr native_compile_context) context) (type u32 scalar_code)
           (type usize reference location words part) (returns c-int))
  (if (= words part) 1
      (let ((code (deref (field-pointer context 'code)))
            (class (native_abi_location_class location))
            (index (wrap+ (native_abi_location_index location) part)))
        (if (= (if (= (native_aggregate_reference_p context reference) 1) (a64_aggregate_load_part context reference part)
                   (a64_lir_load context 9 reference)) 0) 0
            (if (= (cond
                     ((= class 1) (a64_register_op code #xaa000000 (wrap-cast u64 index) 31 9))
                     ((= class 2) (a64_general_to_float code index 9 scalar_code))
                     (t (a64_store_stack_argument code 9 (wrap+ index 9)))) 0) 0
                (a64_aggregate_send_words context reference scalar_code location words (wrap+ part 1)))))))

(defun a64_aggregate_call_result_words (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (destination (deref (field-pointer op 'destination))))
    (if (= (a64_store_frame code 0 (a64_aggregate_offset context destination 0)) 0) 0
        (if (= (if (= (native_aggregate_words context 16 (deref (field-pointer op 'pointee))) 2)
                   (a64_store_frame code 1 (a64_aggregate_offset context destination 1)) (wrap-cast c-int 1)) 0) 0
            (a64_aggregate_address context destination)))))

(defun a64_aggregate_return_words (context reference words)
  (declare (type (ptr native_compile_context) context) (type usize reference words) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (a64_lir_load context 9 reference) 0) 0
        (if (= (a64_memory code 8 0 0 0 9) 0) 0
            (if (= words 1) (a64_return code)
                (if (= (a64_immediate code 10 8) 0) 0
                    (if (= (a64_register_op code #x8b000000 10 9 10) 0) 0
                        (if (= (a64_memory code 8 0 0 1 10) 0) 0 (a64_return code)))))))))

(defun a64_aggregate_reference_type (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns usize))
  (deref (field-pointer (ir_type_at
            (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) reference) 'pointee)))

(defun a64_aggregate_store_field (context destination leaf)
  (declare (type (ptr native_compile_context) context)
           (type usize destination leaf) (returns c-int))
  (if (= (a64_root_address context 10
           (wrap- (a64_aggregate_offset context destination 0) (native_aggregate_leaf_offset leaf))) 0) 0
      (a64_memory (deref (field-pointer context 'code))
                  (native_aggregate_leaf_width leaf) 0 1 9 10)))

(defun a64_aggregate_load_field (context reference leaf)
  (declare (type (ptr native_compile_context) context) (type usize reference leaf) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (a64_lir_load context 9 reference) 0) 0
        (if (= (a64_immediate code 10 (wrap-cast u64 (native_aggregate_leaf_offset leaf))) 0) 0
            (if (= (a64_register_op code #x8b000000 9 9 10) 0) 0
                (a64_memory code (native_aggregate_leaf_width leaf) 0 0 9 9))))))

(defun a64_aggregate_incoming_fields (context destination type index fp)
  (declare (type (ptr native_compile_context) context)
           (type usize destination type index fp) (returns c-int))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) (a64_aggregate_address context destination)
        (if (= (a64_lir_load_abi_parameter context (native_abi_location 2 (wrap+ fp index))) 0) 0
            (if (= (a64_aggregate_store_field context destination leaf) 0) 0
                (a64_aggregate_incoming_fields context destination type (wrap+ index 1) fp))))))

(defun a64_aggregate_incoming (context destination location part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination location part words) (returns c-int))
  (if (= (native_abi_location_class location) 4)
      (a64_aggregate_incoming_fields context destination (a64_aggregate_reference_type context destination)
        0 (native_abi_location_index location))
      (a64_aggregate_incoming_words context destination
        (if (= (native_abi_location_class location) 5)
            (native_abi_location 3 (native_abi_location_index location)) location) part words)))

(defun a64_aggregate_send_fields (context reference type index fp)
  (declare (type (ptr native_compile_context) context)
           (type usize reference type index fp) (returns c-int))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) 1
        (if (= (a64_aggregate_load_field context reference leaf) 0) 0
            (if (= (a64_general_to_float (deref (field-pointer context 'code)) (wrap+ fp index) 9
                     (native_aggregate_leaf_code leaf)) 0) 0
                (a64_aggregate_send_fields context reference type (wrap+ index 1) fp))))))

(defun a64_aggregate_send (context reference scalar_code location words part)
  (declare (type (ptr native_compile_context) context) (type u32 scalar_code)
           (type usize reference location words part) (returns c-int))
  (if (= (native_abi_location_class location) 4)
      (a64_aggregate_send_fields context reference (a64_aggregate_reference_type context reference)
        0 (native_abi_location_index location))
      (a64_aggregate_send_words context reference scalar_code
        (if (= (native_abi_location_class location) 5)
            (native_abi_location 3 (native_abi_location_index location)) location) words part)))

(defun a64_aggregate_receive_fields (context destination type index)
  (declare (type (ptr native_compile_context) context)
           (type usize destination type index) (returns c-int))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) (a64_aggregate_address context destination)
        (if (= (a64_float_to_general (deref (field-pointer context 'code)) 9 index
                 (native_aggregate_leaf_code leaf)) 0) 0
            (if (= (a64_aggregate_store_field context destination leaf) 0) 0
                (a64_aggregate_receive_fields context destination type (wrap+ index 1)))))))

(defun a64_aggregate_call_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((type (deref (field-pointer op 'pointee))))
    (if (< 0 (native_aggregate_hfa_code context type))
        (a64_aggregate_receive_fields context (deref (field-pointer op 'destination)) type 0)
        (a64_aggregate_call_result_words context op))))

(defun a64_aggregate_return (context reference words)
  (declare (type (ptr native_compile_context) context) (type usize reference words) (returns c-int))
  (let ((type (a64_aggregate_reference_type context reference)))
    (if (< 0 (native_aggregate_hfa_code context type))
        (if (= (a64_aggregate_send_fields context reference type 0 0) 0) 0
            (a64_return (deref (field-pointer context 'code))))
        (a64_aggregate_return_words context reference words))))
