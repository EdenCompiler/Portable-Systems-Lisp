;; LP64D integer aggregate locations include the final-GP/stack split case.
(defun rv_aggregate_location (context signature cursor gp fp stack)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize cursor gp fp stack) (returns usize))
  (if (= (native_aggregate_parameter_words context signature cursor) 2)
      (if (< gp 7) (native_abi_location 1 gp)
          (if (= gp 7) (native_abi_location 4 stack) (native_abi_location 3 stack)))
      (rv_lir_argument_location (scalar_signature_parameter_code context signature cursor) gp fp stack)))

(defun rv_aggregate_next_gp (location words gp)
  (declare (type usize location words gp) (returns usize))
  (if (= (native_abi_location_class location) 1) (wrap+ gp words)
      (if (= (native_abi_location_class location) 4) 8 gp)))

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

(defun rv_aggregate_incoming (context destination location part words)
  (declare (type (ptr native_compile_context) context)
           (type usize destination location part words) (returns c-int))
  (if (= part words) (rv_aggregate_address context destination)
      (if (= (rv_lir_load_abi_parameter context (rv_aggregate_part_location location part)) 0) 0
          (if (= (rv_store_frame (deref (field-pointer context 'code)) 5
                   (rv_aggregate_offset context destination part)) 0) 0
              (rv_aggregate_incoming context destination location (wrap+ part 1) words)))))

(defun rv_aggregate_load_part (context reference part)
  (declare (type (ptr native_compile_context) context)
           (type usize reference part) (returns c-int))
  (if (= (rv_lir_load context 5 reference) 0) 0
      (rv_i (deref (field-pointer context 'code)) #x03 5 5 3 (wrap-cast u64 (wrap* part 8)))))

(defun rv_aggregate_send (context location reference words scalar_code part)
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
                    (rv_aggregate_send context location reference words scalar_code (wrap+ part 1))))))))

(defun rv_aggregate_call_result (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (destination (deref (field-pointer op 'destination))))
    (if (= (rv_store_frame code 10 (rv_aggregate_offset context destination 0)) 0) 0
        (if (= (if (= (native_aggregate_words context 16 (deref (field-pointer op 'pointee))) 2)
                   (rv_store_frame code 11 (rv_aggregate_offset context destination 1)) (wrap-cast c-int 1)) 0) 0
            (rv_aggregate_address context destination)))))

(defun rv_aggregate_return (context reference words)
  (declare (type (ptr native_compile_context) context) (type usize reference words) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (rv_lir_load context 5 reference) 0) 0
        (if (= (rv_i code #x03 10 5 3 0) 0) 0
            (if (= (if (= words 2) (rv_i code #x03 11 5 3 8) (wrap-cast c-int 1)) 0) 0 (rv_return code))))))
