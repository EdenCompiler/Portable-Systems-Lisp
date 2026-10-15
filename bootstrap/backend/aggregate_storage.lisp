;; Native aggregates retain source layout metadata in verified IR. All
;; records use immutable frame-owned bytes; ordinary virtual words keep their
;; offsets and hold private addresses for these records. No managed roots or
;; target-visible pointer semantics are introduced by this representation.

(defun native_aggregate_words (context code type)
  (declare (type (ptr native_compile_context) context)
           (type u32 code) (type usize type) (returns usize))
  (if (= code 16)
      (if (< 8 (source_type_size context type)) 2 (wrap-cast usize 1)) 1))

(defun native_aggregate_parameter_words (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type usize index) (returns usize))
  (native_aggregate_words context (scalar_signature_parameter_code context signature index)
                          (scalar_signature_parameter_pointee context signature index)))

(defun native_aggregate_sidecars_p (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer arena 'value_count)) index) 0
        (let ((type (ir_type_at (deref (field-pointer arena 'types)) index)))
          (if (= (deref (field-pointer type 'scalar_code)) 16) 1
              (native_aggregate_sidecars_p context (wrap+ index 1)))))))

(defun native_aggregate_frame_slots (context)
  (declare (type (ptr native_compile_context) context) (returns usize))
  (let ((slots (native_root_frame_slots context))
        (count (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))))
    (if (= slots 0) 0
        (if (= (native_aggregate_sidecars_p context 1) 0) slots
            (if (< (shr64 (wrap-cast u64 (wrap- (wrap-cast usize 0) slots)) 1)
                    (wrap-cast u64 count)) 0
                (wrap+ slots (wrap* count 2)))))))

(defun native_aggregate_word_size_p (size)
  (declare (type usize size) (returns c-int))
  (if (if (= size 1) t (if (= size 2) t (if (= size 4) t (= size 8)))) 1 0))

(defun native_aggregate_target_type_p (context code type)
  (declare (type (ptr native_compile_context) context)
           (type u32 code) (type usize type) (returns c-int))
  (if (= code 16) (source_aggregate_type_p context type) 1))

(defun native_aggregate_target_parameters_p (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize index) (returns c-int))
  (if (= index (deref (field-pointer signature 'arity))) 1
      (if (= (native_aggregate_target_type_p context
               (scalar_signature_parameter_code context signature index)
               (scalar_signature_parameter_pointee context signature index)) 0) 0
          (native_aggregate_target_parameters_p context signature (wrap+ index 1)))))

(defun native_aggregate_target_signature_p (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns c-int))
  (if (= (native_aggregate_target_type_p context (scalar_signature_type_code context signature)
           (scalar_signature_result_pointee context signature)) 0) 0
      (native_aggregate_target_parameters_p context signature 0)))

(defun native_aggregate_target_values_p (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer arena 'value_count)) index) 1
        (let ((type (ir_type_at (deref (field-pointer arena 'types)) index)))
          (if (= (native_aggregate_target_type_p context (deref (field-pointer type 'scalar_code))
                   (deref (field-pointer type 'pointee))) 0) 0
              (native_aggregate_target_values_p context (wrap+ index 1)))))))

(defun native_aggregate_target_function_p (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (if (if (= (native_aggregate_frame_slots context) 0)
          (< 0 (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count))) nil) 0
      (if (= (native_aggregate_target_signature_p context
               (deref (field-pointer context 'current_signature))) 0) 0
          (native_aggregate_target_values_p context 1))))

(defun native_aggregate_reference_p (context reference)
  (declare (type (ptr native_compile_context) context) (type usize reference) (returns c-int))
  (if (= (deref (field-pointer (ir_type_at
           (deref (field-pointer (deref (field-pointer context 'lir)) 'types)) reference) 'scalar_code)) 16) 1 0))
