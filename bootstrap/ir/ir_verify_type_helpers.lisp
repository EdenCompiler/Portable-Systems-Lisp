;; Shared source type helpers for the native IR verifiers.

(defun native_closure_plan_target_p (context plan-index target source)
  (declare (type (ptr native_compile_context) context)
           (type usize plan-index target source) (returns c-int))
  (if (= plan-index 0) 0
      (if (< (deref (field-pointer context 'closure_plan_count)) plan-index) 0
          (let ((plans (deref (field-pointer context 'closure_plans))))
            (if (= (ptr-address plans) 0) 0
                (let ((plan (pointer+ plans
                                     (wrap-cast isize (wrap- plan-index 1)))))
                  (if (= (deref (field-pointer plan 'origin)) source)
                      (if (= (deref (field-pointer plan 'function_index))
                             (wrap- target 1)) 1 0) 0)))))))

(defun native_closure_callback_target_p (context target source)
  (declare (type (ptr native_compile_context) context)
           (type usize target source) (returns c-int))
  (cond
    ((= source 0) 0)
    ((= target 0) 0)
    ((< (deref (field-pointer context 'prior_count)) target) 0)
    ((= (native_function_defined_target_p
         (deref (field-pointer context 'functions))
         (deref (field-pointer context 'prior_count)) target) 0) 0)
    (t (native_closure_signature_target_p
        context (native_signature_at
                 (deref (field-pointer context 'signatures))
                 (wrap- target 1)) target source))))

(defun native_closure_signature_target_p (context signature target source)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize target source) (returns c-int))
  (if (= (deref (field-pointer signature 'generated)) 1)
      (if (= (deref (field-pointer signature 'generated_origin)) source)
          (native_closure_plan_target_p
           context (deref (field-pointer signature 'generated_plan)) target source)
          (wrap-cast c-int 0))
      (wrap-cast c-int 0)))

(defun ir_types_same_p (context types reference code pointee)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type usize reference pointee)
           (type u32 code) (returns c-int))
  (let ((type (ir_type_at types reference)))
    (source_types_equal_p context (deref (field-pointer type 'scalar_code))
                          (deref (field-pointer type 'pointee)) code pointee)))

(defun ir_operand_matches_op_p (context types reference op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ir_type) types)
           (type (ptr native_scalar_op) op)
           (type usize reference) (returns c-int))
  (ir_types_same_p context types reference (deref (field-pointer op 'scalar_code))
                   (deref (field-pointer op 'pointee))))

(defun ir_source_type_p (context code pointee)
  (declare (type (ptr native_compile_context) context)
           (type u32 code) (type usize pointee) (returns c-int))
  (if (= code 16) (source_aggregate_type_p context pointee)
  (if (= code 11)
      (source_pointer_pointee_p context pointee)
      (if (= pointee 0)
          (if (= code 0) 1 (if (= code 12) 1 (source_context_code_p context code))) 0))))
