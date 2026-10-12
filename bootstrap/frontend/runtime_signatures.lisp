;; Resolved runtime ABI v1 signatures. No source AST or parser-node sentinel
;; supplies the types of these compiler-owned imports.
(defun native_runtime_name (id)
  (declare (type u32 id) (returns (ptr u8)))
  (cond
    ((= id 1) (ffi:c-string "psl_rt_cons_precise"))
    ((= id 2) (ffi:c-string "psl_rt_car"))
    ((= id 3) (ffi:c-string "psl_rt_cdr"))
    ((= id 4) (ffi:c-string "psl_rt_fixnum"))
    ((= id 5) (ffi:c-string "psl_rt_unbox_fixnum"))
    ((= id 6) (ffi:c-string "psl_rt_collect_precise"))
    ((= id 7) (ffi:c-string "psl_rt_push_roots"))
    ((= id 8) (ffi:c-string "psl_rt_pop_roots"))
    ((= id 9) (ffi:c-string "psl_rt_eq"))
    ((= id 10) (ffi:c-string "psl_rt_truthy"))
    (t (ptr-from-address (ptr u8) 0))))

(defun native_runtime_name_length (id)
  (declare (type u32 id) (returns usize))
  (cond
    ((= id 1) 19)
    ((= id 2) 10)
    ((= id 3) 10)
    ((= id 4) 13)
    ((= id 5) 19)
    ((= id 6) 22)
    ((= id 7) 17)
    ((= id 8) 16)
    ((= id 9) 9)
    ((= id 10) 13)
    (t 0)))

(defun native_runtime_arity (id)
  (declare (type u32 id) (returns usize))
  (cond ((= id 1) 2) ((= id 6) 0) ((= id 7) 3) ((= id 9) 2) (t 1)))

(defun native_runtime_result (id)
  (declare (type u32 id) (returns u32))
  (cond ((= id 5) 9) ((= id 6) 12) ((= id 7) 12) ((= id 8) 12)
        ((= id 9) 0) ((= id 10) 0) (t 15)))

(defun native_runtime_parameter (id index)
  (declare (type u32 id) (type usize index) (returns u32))
  (cond ((= id 4) 9)
        ((= id 7) (if (= index 2) (wrap-cast u32 2) (wrap-cast u32 1)))
        ((= id 8) 1) (t 15)))

(defun native_runtime_free_p (id)
  (declare (type u32 id) (returns u8))
  (if (= id 1) (wrap-cast u8 0) (if (= id 6) (wrap-cast u8 0) (wrap-cast u8 1))))

(defun native_runtime_parameter_p (parameter id index)
  (declare (type (ptr native_parameter) parameter) (type u32 id) (type usize index) (returns c-int))
  (let ((code (native_runtime_parameter id index)))
    (if (= (deref (field-pointer parameter 'name)) 0)
        (if (= (deref (field-pointer parameter 'type_ast)) 0)
            (if (= (deref (field-pointer parameter 'scalar_code)) code)
                (if (= (deref (field-pointer parameter 'size)) 8)
                    (if (= (deref (field-pointer parameter 'kind))
                           (if (= code 15) (wrap-cast u32 5) (wrap-cast u32 1))) 1 0) 0) 0) 0) 0)))

(defun native_runtime_parameters_from_p (signatures signature id index)
  (declare (type (ptr native_signature_context) signatures)
           (type (ptr native_signature) signature) (type u32 id) (type usize index) (returns c-int))
  (if (= index (native_runtime_arity id)) 1
      (if (= (native_runtime_parameter_p
              (native_parameter_at signatures (wrap+ (deref (field-pointer signature 'first_parameter)) index)) id index) 0) 0
          (native_runtime_parameters_from_p signatures signature id (wrap+ index 1)))))

(defun native_runtime_parameters_p (context signature id)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (type u32 id) (returns c-int))
  (let ((signatures (deref (field-pointer context 'signatures)))
        (first (deref (field-pointer signature 'first_parameter))))
    (if (< (deref (field-pointer signatures 'parameter_count)) first) 0
        (if (< (wrap- (deref (field-pointer signatures 'parameter_count)) first) (native_runtime_arity id)) 0
            (native_runtime_parameters_from_p signatures signature id 0)))))

(defun native_runtime_header_p (signature id)
  (declare (type (ptr native_signature) signature) (type u32 id) (returns c-int))
  (if (= (deref (field-pointer signature 'name)) 0)
      (if (= (deref (field-pointer signature 'result_type)) 0)
          (if (= (deref (field-pointer signature 'body)) 0)
              (if (= (deref (field-pointer signature 'imported)) 1)
                  (if (= (deref (field-pointer signature 'exported)) 0)
                      (if (= (deref (field-pointer signature 'allocation_free)) (native_runtime_free_p id))
                          (if (= (deref (field-pointer signature 'effect_ready)) 1) 1 0) 0) 0) 0) 0) 0) 0))

(defun native_runtime_result_p (signature id)
  (declare (type (ptr native_signature) signature) (type u32 id) (returns c-int))
  (let ((code (native_runtime_result id)))
    (if (= (deref (field-pointer signature 'arity)) (native_runtime_arity id))
        (if (= (deref (field-pointer signature 'result_code)) code)
            (if (= (deref (field-pointer signature 'result_size))
                   (if (= code 12) (wrap-cast usize 0) (wrap-cast usize 8)))
                (if (= (deref (field-pointer signature 'result_kind))
                       (if (= code 12) (wrap-cast u32 4)
                           (if (= code 15) (wrap-cast u32 5) (wrap-cast u32 1)))) 1 0) 0) 0) 0)))

(defun native_runtime_signature_name_p (signature id)
  (declare (type (ptr native_signature) signature) (type u32 id) (returns c-int))
  (let ((name (deref (field-pointer signature 'runtime_name)))
        (length (deref (field-pointer signature 'runtime_name_length))))
    (if (= (ptr-address name) 0) 0
        (if (= length (native_runtime_name_length id))
            (same_name_bytes_p name (native_runtime_name id) length) 0))))

(defun native_runtime_signature_p (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns c-int) (c-export :c))
  (let ((id (deref (field-pointer signature 'runtime_id))))
    (if (= (deref (field-pointer context 'profile)) 1)
        (if (= id 0) 0
            (if (< 10 id) 0
                (if (= (native_runtime_signature_name_p signature id) 0) 0
                    (if (= (native_runtime_header_p signature id) 0) 0
                        (if (= (native_runtime_result_p signature id) 0) 0
                            (native_runtime_parameters_p context signature id)))))) 0)))

(defun native_runtime_initialize_parameter (parameter id index)
  (declare (type (ptr native_parameter) parameter) (type u32 id) (type usize index) (returns c-int))
  (let ((code (native_runtime_parameter id index)))
    (store (field-pointer parameter 'name) 0)
    (store (field-pointer parameter 'type_ast) 0)
    (store (field-pointer parameter 'size) 8)
    (store (field-pointer parameter 'kind) (if (= code 15) (wrap-cast u32 5) (wrap-cast u32 1)))
    (store (field-pointer parameter 'scalar_code) code)
    1))

(defun native_runtime_initialize_signature (signature id first)
  (declare (type (ptr native_signature) signature) (type u32 id) (type usize first) (returns c-int))
  (let ((code (native_runtime_result id)))
    (store (field-pointer signature 'name) 0)
    (store (field-pointer signature 'first_parameter) first)
    (store (field-pointer signature 'arity) (native_runtime_arity id))
    (store (field-pointer signature 'result_type) 0)
    (store (field-pointer signature 'result_size) (if (= code 12) (wrap-cast usize 0) (wrap-cast usize 8)))
    (store (field-pointer signature 'result_kind)
           (if (= code 12) (wrap-cast u32 4) (if (= code 15) (wrap-cast u32 5) (wrap-cast u32 1))))
    (store (field-pointer signature 'body) 0)
    (store (field-pointer signature 'exported) 0)
    (store (field-pointer signature 'imported) 1)
    (store (field-pointer signature 'allocation_free) (native_runtime_free_p id))
    (store (field-pointer signature 'effect_ready) 1)
    (store (field-pointer signature 'inline_base) 0)
    (store (field-pointer signature 'inline_count) 0)
    (store (field-pointer signature 'inline_result) 0)
    (store (field-pointer signature 'runtime_id) id)
    (store (field-pointer signature 'result_code) code)
    (store (field-pointer signature 'runtime_name) (native_runtime_name id))
    (store (field-pointer signature 'runtime_name_length) (native_runtime_name_length id))
    1))

(defun native_runtime_initialize_parameters (signatures id first index)
  (declare (type (ptr native_signature_context) signatures) (type u32 id)
           (type usize first index) (returns c-int))
  (if (= index (native_runtime_arity id)) 1
      (progn
        (native_runtime_initialize_parameter (native_parameter_at signatures (wrap+ first index)) id index)
        (native_runtime_initialize_parameters signatures id first (wrap+ index 1)))))

(defun native_runtime_initialize_catalog (signatures id count first)
  (declare (type (ptr native_signature_context) signatures) (type u32 id)
           (type usize count first) (returns c-int))
  (if (= id 11) 1
      (progn
        (native_runtime_initialize_signature
         (native_signature_at signatures (wrap+ count (wrap-cast usize (wrap- id 1)))) id first)
        (native_runtime_initialize_parameters signatures id first 0)
        (native_runtime_initialize_catalog signatures (wrap+ id 1) count (wrap+ first (native_runtime_arity id))))))

(defun native_runtime_symbol_used_p (context id index)
  (declare (type (ptr native_compile_context) context) (type u32 id) (type usize index) (returns c-int))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (if (= index (deref (field-pointer signatures 'signature_count))) 0
        (let ((function (native_function_at (deref (field-pointer context 'functions)) index))
              (signature (native_signature_at signatures index)))
          (if (< 0 (deref (field-pointer signature 'runtime_id))) 1
              (if (= (deref (field-pointer function 'name_length)) (native_runtime_name_length id))
                  (if (= (same_name_bytes_p (deref (field-pointer function 'name))
                                            (native_runtime_name id) (native_runtime_name_length id)) 1) 1
                      (native_runtime_symbol_used_p context id (wrap+ index 1)))
                  (native_runtime_symbol_used_p context id (wrap+ index 1))))))))

(defun native_runtime_data_used_p (context id index)
  (declare (type (ptr native_compile_context) context) (type u32 id) (type usize index) (returns c-int))
  (if (= index (deref (field-pointer context 'data_count))) 0
      (let ((entry (native_data_import_at context index)))
        (if (= (deref (field-pointer entry 'global)) 0)
            (native_runtime_data_used_p context id (wrap+ index 1))
            (if (= (deref (field-pointer entry 'name_length)) (native_runtime_name_length id))
                (if (= (same_name_bytes_p (deref (field-pointer entry 'name))
                                          (native_runtime_name id) (native_runtime_name_length id)) 1) 1
                    (native_runtime_data_used_p context id (wrap+ index 1)))
                (native_runtime_data_used_p context id (wrap+ index 1)))))))

(defun native_runtime_names_free_p (context id)
  (declare (type (ptr native_compile_context) context) (type u32 id) (returns c-int))
  (if (= id 11) 1
      (if (= (native_runtime_symbol_used_p context id 0) 1) 0
          (if (= (native_runtime_data_used_p context id 0) 1) 0
              (native_runtime_names_free_p context (wrap+ id 1))))))

(defun native_runtime_function_index (context id index)
  (declare (type (ptr native_compile_context) context) (type u32 id) (type usize index) (returns usize))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (if (= index (deref (field-pointer signatures 'signature_count))) 0
        (if (= (deref (field-pointer (native_signature_at signatures index) 'runtime_id)) id)
            (wrap+ index 1) (native_runtime_function_index context id (wrap+ index 1))))))

(defun native_runtime_storage_ready_p (signatures)
  (declare (type (ptr native_signature_context) signatures) (returns c-int))
  (let ((count (deref (field-pointer signatures 'signature_count)))
        (first (deref (field-pointer signatures 'parameter_count)))
        (capacity (deref (field-pointer signatures 'signature_capacity)))
        (parameter_capacity (deref (field-pointer signatures 'parameter_capacity))))
    (if (= (ptr-address (deref (field-pointer signatures 'signatures))) 0) 0
        (if (= (ptr-address (deref (field-pointer signatures 'parameters))) 0) 0
            (if (< capacity count) 0
                (if (< (wrap- capacity count) 10) 0
                    (if (< parameter_capacity first) 0
                        (if (< (wrap- parameter_capacity first) 13) 0 1))))))))

;; Reserve both tables before reading source symbols or writing records. Publish
;; their counts only after construction; failed validation leaves them unchanged.
(defun native_register_runtime_signatures (context)
  (declare (type (ptr native_compile_context) context) (returns c-int) (c-export :c))
  (if (= (deref (field-pointer context 'profile)) 1)
      (let ((signatures (deref (field-pointer context 'signatures))))
        (if (= (ptr-address signatures) 0) 0
            (if (= (native_runtime_storage_ready_p signatures) 0) 0
                (if (= (native_runtime_names_free_p context 1) 0) 0
                    (let ((count (deref (field-pointer signatures 'signature_count)))
                          (first (deref (field-pointer signatures 'parameter_count))))
                      (native_runtime_initialize_catalog signatures 1 count first)
                      (store (field-pointer signatures 'signature_count) (wrap+ count 10))
                      (store (field-pointer signatures 'parameter_count) (wrap+ first 13))
                      1))))) 0))

(defun native_runtime_call_signature_p (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns c-int))
  (let ((id (deref (field-pointer signature 'runtime_id))))
    (if (= id 0) 1
        (if (if (= id 7) t (= id 8)) 0
            (native_runtime_signature_p context signature)))))
