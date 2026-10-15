;; LP64D integer aggregate locations include the final-GP/stack split case.
(defun rv_aggregate_special_p (context type)
  (declare (type (ptr native_compile_context) context) (type usize type) (returns c-int))
  (let ((count (native_aggregate_leaf_count context type))
        (floats (native_aggregate_float_leaf_count context type 0)))
    (if (if (< 2 count) t (= floats 0)) 0 1)))

(defun rv_aggregate_field_count (context type floating)
  (declare (type (ptr native_compile_context) context) (type usize type)
           (type c-int floating) (returns usize))
  (let ((floats (native_aggregate_float_leaf_count context type 0)))
    (if (= floating 1) floats (wrap- (native_aggregate_leaf_count context type) floats))))

(defun rv_aggregate_location (context signature cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize cursor gp fp stack) (returns usize))
  (let ((code (scalar_signature_parameter_code context signature cursor))
        (type (scalar_signature_parameter_pointee context signature cursor)))
    (if (if (= code 16) (= (rv_aggregate_special_p context type) 1) nil)
        (if (if (< 8 (wrap+ gp (rv_aggregate_field_count context type 0))) t
                (< 8 (wrap+ fp (rv_aggregate_field_count context type 1))))
            (rv_aggregate_general_location context signature cursor gp fp stack)
            (native_abi_location 5 (wrap+ gp (wrap* fp 16))))
        (rv_aggregate_general_location context signature cursor gp fp stack))))

(defun rv_aggregate_general_location (context signature cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize cursor gp fp stack) (returns usize))
  (if (= (native_aggregate_parameter_words context signature cursor) 2)
      (if (< gp 7) (native_abi_location 1 gp)
          (if (= gp 7) (native_abi_location 4 stack) (native_abi_location 3 stack)))
      (rv_lir_argument_location (scalar_signature_parameter_code context signature cursor) gp fp stack)))

(defun rv_aggregate_next_gp (context signature cursor location words gp)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize cursor location words gp) (returns usize))
  (if (= (native_abi_location_class location) 5)
      (wrap+ gp (rv_aggregate_field_count context
                  (scalar_signature_parameter_pointee context signature cursor) 0))
      (if (= (native_abi_location_class location) 1) (wrap+ gp words)
          (if (= (native_abi_location_class location) 4) 8 gp))))

(defun rv_aggregate_next_fp (context signature cursor location fp)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize cursor location fp) (returns usize))
  (if (= (native_abi_location_class location) 5)
      (wrap+ fp (rv_aggregate_field_count context
                  (scalar_signature_parameter_pointee context signature cursor) 1))
      (rv_lir_next_fp location fp)))

(defun rv_aggregate_next_stack (location words stack)
  (declare (type usize location words stack) (returns usize))
  (if (= (native_abi_location_class location) 3) (wrap+ stack words)
      (if (= (native_abi_location_class location) 4) (wrap+ stack 1) stack)))

(defun rv_aggregate_part_location (location part)
  (declare (type usize location part) (returns usize))
  (let ((class (native_abi_location_class location)) (index (native_abi_location_index location)))
    (if (= class 4)
        (if (= part 0) (native_abi_location 1 7) (native_abi_location 3 index))
        (native_abi_location class (wrap+ index part)))))

(defun rv_aggregate_offset (context reference part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference part) (returns usize))
  (wrap- (rv_local_offset (wrap+ (native_root_frame_slots context) (wrap* reference 2)))
         (wrap* part 8)))

(defun rv_aggregate_address (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns c-int))
  (rv_root_address context 5 (rv_aggregate_offset context reference 0)))

(defun rv_aggregate_incoming_words (context destination location part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination location part words) (returns c-int))
  (if (= part words) (rv_aggregate_address context destination)
      (if (= (rv_lir_load_abi_parameter context (rv_aggregate_part_location location part)) 0) 0
          (if (= (rv_store_frame (deref (field-pointer context 'code)) 5
                   (rv_aggregate_offset context destination part)) 0) 0
              (rv_aggregate_incoming_words context destination location (wrap+ part 1) words)))))

(defun rv_aggregate_load_part (context reference part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference part) (returns c-int))
  (if (= (rv_lir_load context 5 reference) 0) 0
      (rv_i (deref (field-pointer context 'code)) #x03 5 5 3 (wrap-cast u64 (wrap* part 8)))))

(defun rv_aggregate_send_words (context location reference words scalar_code part)
  (declare (type (ptr native_compile_context) context) (type u32 scalar_code)
           (type usize location reference words part) (returns c-int))
  (if (= (native_aggregate_reference_p context reference) 0) (rv_lir_send_argument context location reference scalar_code)
      (if (= words part) 1
          (let ((destination (rv_aggregate_part_location location part))
                (code (deref (field-pointer context 'code))))
            (if (= (rv_aggregate_load_part context reference part) 0) 0
                (if (= (if (= (native_abi_location_class destination) 1)
                            (rv_move code (wrap-cast u64 (wrap+ 10 (native_abi_location_index destination))) 5)
                            (rv_store_stack_argument code 5 (wrap+ 9 (native_abi_location_index destination)))) 0) 0
                    (rv_aggregate_send_words context location reference words scalar_code (wrap+ part 1))))))))

(defun rv_aggregate_call_result_words (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (destination (deref (field-pointer op 'destination))))
    (if (= (rv_store_frame code 10 (rv_aggregate_offset context destination 0)) 0) 0
        (if (= (if (= (native_aggregate_words context 16 (deref (field-pointer op 'pointee))) 2)
                   (rv_store_frame code 11 (rv_aggregate_offset context destination 1)) (wrap-cast c-int 1)) 0) 0
            (rv_aggregate_address context destination)))))

(defun rv_aggregate_return_words (context reference words)
  (declare (type (ptr native_compile_context) context) (type usize reference words) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (rv_lir_load context 5 reference) 0) 0
        (if (= (rv_i code #x03 10 5 3 0) 0) 0
            (if (= (if (= words 2) (rv_i code #x03 11 5 3 8) (wrap-cast c-int 1)) 0) 0 (rv_return code))))))

(defun rv_aggregate_reference_type (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns usize))
  (deref (field-pointer (ir_type_at
            (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) reference) 'pointee)))

(defun rv_aggregate_field_register_index (context type end class index count)
  (declare (type (ptr native_compile_context) context)
           (type usize type end class index count) (returns usize))
  (if (= index end) count
      (let ((floating (native_abi_float_p (native_aggregate_leaf_code
                       (native_aggregate_leaf context type index)))))
        (rv_aggregate_field_register_index context type end class (wrap+ index 1)
          (if (if (= class 2) (= floating 1) (= floating 0)) (wrap+ count 1) count)))))

(defun rv_aggregate_field_location (context type location index)
  (declare (type (ptr native_compile_context) context)
           (type usize type location index) (returns usize))
  (let ((packet (native_abi_location_index location))
        (code (native_aggregate_leaf_code (native_aggregate_leaf context type index))))
    (let ((class (if (= (native_abi_float_p code) 1) (wrap-cast usize 2) (wrap-cast usize 1))))
      (native_abi_location class
        (wrap+ (if (= class 1) (bits-and packet 15)
                   (wrap-cast usize (shr64 (wrap-cast u64 packet) 4)))
               (rv_aggregate_field_register_index context type index class 0 0))))))

(defun rv_aggregate_store_field (context destination leaf)
  (declare (type (ptr native_compile_context) context) (type usize destination leaf) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (width (native_aggregate_leaf_width leaf)))
    (if (= (rv_move code 6 5) 0) 0
        (if (= (rv_root_address context 5
                 (wrap- (rv_aggregate_offset context destination 0) (native_aggregate_leaf_offset leaf))) 0) 0
            (rv_s code 5 6 (if (= width 1) (wrap-cast u64 0)
                              (if (= width 2) (wrap-cast u64 1)
                                  (if (= width 4) (wrap-cast u64 2) (wrap-cast u64 3)))) 0)))))

(defun rv_aggregate_load_field (context reference leaf)
  (declare (type (ptr native_compile_context) context) (type usize reference leaf) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (width (native_aggregate_leaf_width leaf)))
    (if (= (rv_lir_load context 5 reference) 0) 0
        (rv_i code #x03 5 5 (if (= width 1) (wrap-cast u64 4)
                               (if (= width 2) (wrap-cast u64 5)
                                   (if (= width 4) (wrap-cast u64 6) (wrap-cast u64 3))))
          (wrap-cast u64 (native_aggregate_leaf_offset leaf))))))

(defun rv_aggregate_incoming_fields (context destination type location index)
  (declare (type (ptr native_compile_context) context)
           (type usize destination type location index) (returns c-int))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) (rv_aggregate_address context destination)
        (if (= (rv_lir_load_abi_parameter context (rv_aggregate_field_location context type location index)) 0) 0
            (if (= (rv_aggregate_store_field context destination leaf) 0) 0
                (rv_aggregate_incoming_fields context destination type location (wrap+ index 1)))))))

(defun rv_aggregate_incoming (context destination location part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination location part words) (returns c-int))
  (if (= (native_abi_location_class location) 5)
      (rv_aggregate_incoming_fields context destination (rv_aggregate_reference_type context destination) location 0)
      (rv_aggregate_incoming_words context destination location part words)))

(defun rv_aggregate_send_field (context reference leaf location)
  (declare (type (ptr native_compile_context) context)
           (type usize reference leaf location) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (index (native_abi_location_index location))
        (scalar_code (native_aggregate_leaf_code leaf)))
    (if (= (rv_aggregate_load_field context reference leaf) 0) 0
        (if (= (native_abi_location_class location) 2)
            (rv_general_to_float code (wrap+ 10 index) 5 scalar_code)
            (if (= (rv_abi_normalize code 5 scalar_code) 0) 0
                (rv_move code (wrap-cast u64 (wrap+ 10 index)) 5))))))

(defun rv_aggregate_send_fields (context reference type location index)
  (declare (type (ptr native_compile_context) context)
           (type usize reference type location index) (returns c-int))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) 1
        (if (= (rv_aggregate_send_field context reference leaf
                 (rv_aggregate_field_location context type location index)) 0) 0
            (rv_aggregate_send_fields context reference type location (wrap+ index 1))))))

(defun rv_aggregate_send (context location reference words scalar_code part)
  (declare (type (ptr native_compile_context) context) (type u32 scalar_code)
           (type usize location reference words part) (returns c-int))
  (if (= (native_abi_location_class location) 5)
      (rv_aggregate_send_fields context reference (rv_aggregate_reference_type context reference) location 0)
      (rv_aggregate_send_words context location reference words scalar_code part)))

(defun rv_aggregate_receive_field (context destination leaf location)
  (declare (type (ptr native_compile_context) context)
           (type usize destination leaf location) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (index (wrap+ 10 (native_abi_location_index location))))
    (if (= (if (= (native_abi_location_class location) 2)
                (rv_float_to_general code 5 index (native_aggregate_leaf_code leaf))
                (rv_move code 5 (wrap-cast u64 index))) 0) 0
        (rv_aggregate_store_field context destination leaf))))

(defun rv_aggregate_receive_fields (context destination type index)
  (declare (type (ptr native_compile_context) context)
           (type usize destination type index) (returns c-int))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) (rv_aggregate_address context destination)
        (if (= (rv_aggregate_receive_field context destination leaf
                 (rv_aggregate_field_location context type (native_abi_location 5 0) index)) 0) 0
            (rv_aggregate_receive_fields context destination type (wrap+ index 1))))))

(defun rv_aggregate_call_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((type (deref (field-pointer op 'pointee))))
    (if (= (rv_aggregate_special_p context type) 1)
        (rv_aggregate_receive_fields context (deref (field-pointer op 'destination)) type 0)
        (rv_aggregate_call_result_words context op))))

(defun rv_aggregate_return (context reference words)
  (declare (type (ptr native_compile_context) context) (type usize reference words) (returns c-int))
  (let ((type (rv_aggregate_reference_type context reference)))
    (if (= (rv_aggregate_special_p context type) 1)
        (if (= (rv_aggregate_send_fields context reference type (native_abi_location 5 0) 0) 0) 0
            (rv_return (deref (field-pointer context 'code))))
        (rv_aggregate_return_words context reference words))))
