;; Collect bounded pure SSA templates once, before compiling caller bodies.
;; The cache is caller-owned; a missing/full cache leaves valid calls in place.

(defun native_prepare_inline_function (context result)
  (declare (type (ptr native_compile_context) context) (type (ptr native_unit_result) result)
           (returns c-int))
  (let ((signature (native_unit_signature context result)))
    (if (= (deref (field-pointer signature 'imported)) 1) 1
        (let ((root (analyze_verified_scalar_function context signature)))
          (if (= root 0) (native_unit_fail result 6)
              (if (= (ssa_lower_function context root) 0) (native_unit_fail result 6)
                  (if (= (ssa_verify_function context) 0) (native_unit_fail result 6)
                      (if (= (ssa_inline_body_p (deref (field-pointer context 'ssa))) 0) 1
                          (ssa_inline_save_body context signature)))))))))

(defun native_prepare_inline_unit (context result count)
  (declare (type (ptr native_compile_context) context) (type (ptr native_unit_result) result)
           (type usize count) (returns c-int))
  (store (field-pointer context 'inline_count) 0)
  (if (= (deref (field-pointer context 'optimization)) 0) 1
      (if (= (deref (field-pointer context 'inline_capacity)) 0) 1
          (progn
            (store (field-pointer result 'index) 0)
            (while (= (native_unit_pending_p result count) 1)
              (if (= (native_prepare_inline_function context result) 1)
                  (progn (native_next_signature result) (wrap-cast c-int 1))
                  (native_unit_fail result 6)))
            (if (= (deref (field-pointer result 'phase)) 0) 1 0)))))
