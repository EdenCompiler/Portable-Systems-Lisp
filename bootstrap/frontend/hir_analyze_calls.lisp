;; Direct calls use resolved signature records for each argument and result.

(defun hir_build_call_chain (context argument signature index previous depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize argument index previous depth) (returns usize))
  (if (= index (deref (field-pointer signature 'arity)))
      previous
      (let ((parser (deref (field-pointer context 'parser)))
            (arena (deref (field-pointer context 'hir))))
        (let ((code (scalar_signature_parameter_code context signature index)))
          (let ((value (analyze_source_expected
                        context argument code
                        (scalar_signature_parameter_pointee context signature index)
                        (wrap+ depth 1))))
            (if (= value 0)
                0
                (let ((link (hir_copy_type arena
                             (hir_new_scalar arena 17 0 value previous 0
                                             argument code) value)))
                  (if (= link 0)
                      0
                      (hir_build_call_chain
                       context (ast_next parser argument) signature
                       (wrap+ index 1) link depth)))))))))

(defun hir_from_call_arguments (context body name index signature depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize body name index depth) (returns usize))
  (let ((arena (deref (field-pointer context 'hir)))
        (parser (deref (field-pointer context 'parser)))
        (code (scalar_signature_type_code context signature)))
    (if (= (deref (field-pointer signature 'arity)) 0)
        (hir_with_pointee arena
         (hir_new_scalar arena 7 0 0 0 index body code)
         (scalar_signature_result_pointee context signature))
        (let ((chain (hir_build_call_chain
                      context (ast_next parser name) signature 0 0 depth)))
          (if (= chain 0)
              0
              (hir_with_pointee arena
               (hir_new_scalar arena 7 0 chain 0 index body code)
               (scalar_signature_result_pointee context signature)))))))

(defun hir_from_resolved_call (context body name index depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body name index depth) (returns usize))
  (let ((signature
         (native_signature_at (deref (field-pointer context 'signatures))
                              (wrap- index 1))))
    (if (= (call_shape_p (deref (field-pointer context 'parser)) name
                         (deref (field-pointer signature 'arity))) 0)
        0
        (hir_from_call_arguments context body name index signature depth))))

(defun hir_from_call (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((name (ast_first (deref (field-pointer context 'parser)) body)))
    (if (= name 0)
        0
        (let ((index (prior_function_index
                      context name
                      (deref (field-pointer context 'prior_count)))))
          (if (= index 0)
              0
              (hir_from_resolved_call context body name index depth))))))
