;; A greatest fixed point admits pure recursive groups and removes every
;; function that reaches an uncertified import. HIR is rebuilt in scratch
;; storage rather than retaining a second arena for every function.

(defun native_infer_function_effect (context result)
  (declare (type (ptr native_compile_context) context) (type (ptr native_unit_result) result)
           (returns c-int))
  (let ((signature (native_unit_signature context result)))
    (if (= (deref (field-pointer signature 'imported)) 1) 1
        (if (= (deref (field-pointer signature 'allocation_free)) 0) 1
            (let ((root (analyze_verified_scalar_function context signature)))
              (if (= root 0) (native_unit_fail result 6)
                  (progn
                    (if (= (hir_function_unsafe_call context 1) 0) (wrap-cast u8 1)
                        (progn
                          (store (field-pointer context 'effects_changed) 1)
                          (store (field-pointer signature 'allocation_free) 0)))
                    1)))))))

(defun native_infer_effect_pass (context result count)
  (declare (type (ptr native_compile_context) context) (type (ptr native_unit_result) result)
           (type usize count) (returns c-int))
  (store (field-pointer result 'index) 0)
  (store (field-pointer context 'effects_changed) 0)
  (while (= (native_unit_pending_p result count) 1)
    (if (= (native_infer_function_effect context result) 1)
        (native_next_signature result) (wrap-cast usize 0)))
  (if (= (deref (field-pointer result 'phase)) 0) 1 0))

(defun native_finish_effects (context index count)
  (declare (type (ptr native_compile_context) context) (type usize index count) (returns c-int))
  (if (= index count) 1
      (progn
        (store (field-pointer (native_signature_at (deref (field-pointer context 'signatures)) index)
                              'effect_ready) 1)
        (native_finish_effects context (wrap+ index 1) count))))

(defun native_check_function_regions (context result)
  (declare (type (ptr native_compile_context) context) (type (ptr native_unit_result) result)
           (returns c-int))
  (let ((signature (native_unit_signature context result)))
    (if (= (deref (field-pointer signature 'imported)) 1) 1
        (let ((root (analyze_verified_scalar_function context signature)))
          (if (= root 0) (native_unit_fail result 6)
              (let ((unsafe (hir_regions_unsafe_call context 1)))
                (if (= unsafe 0) 1
                    (progn
                      (store (field-pointer result 'form)
                             (deref (field-pointer (native_signature_at
                               (deref (field-pointer context 'signatures)) (wrap- unsafe 1)) 'name)))
                      (native_unit_fail result 9)))))))))

(defun native_check_unit_regions (context result count)
  (declare (type (ptr native_compile_context) context) (type (ptr native_unit_result) result)
           (type usize count) (returns c-int))
  (store (field-pointer result 'index) 0)
  (while (= (native_unit_pending_p result count) 1)
    (if (= (native_check_function_regions context result) 1)
        (native_next_signature result) (wrap-cast usize 0)))
  (if (= (deref (field-pointer result 'phase)) 0) 1 0))

(defun native_certify_effects (context result count)
  (declare (type (ptr native_compile_context) context) (type (ptr native_unit_result) result)
           (type usize count) (returns c-int))
  (store (field-pointer context 'prior_count) count)
  (store (field-pointer context 'effects_changed) 1)
  (while (if (= (deref (field-pointer result 'phase)) 0)
             (= (deref (field-pointer context 'effects_changed)) 1) nil)
    (native_infer_effect_pass context result count))
  (if (= (deref (field-pointer result 'phase)) 0)
      (progn
        (native_finish_effects context 0 count)
        (native_check_unit_regions context result count)) 0))
