;; The documented two-value subset lowers through existing lexical HIR.
(defun native_values_form_p (context body)
  (declare (type (ptr native_compile_context) context) (type usize body) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (ast_list_p parser body) 0) 0
        (ast_package_name_p parser (ast_first parser body) 1 (ffi:c-string "VALUES") 6))))

(defun native_mvb_name_p (context name)
  (declare (type (ptr native_compile_context) context) (type usize name) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (ast_variable_name_p parser (deref (field-pointer context 'source)) name) 0) 0
        (let ((symbol (ast_symbol_identity parser name))
              (reader (deref (field-pointer parser 'environment))))
          (if (= symbol 0) 0
              (let ((env (deref (field-pointer reader 'environment))))
                (if (= (deref (field-pointer (native_ct_symbol_at env symbol) 'package))
                       (deref (field-pointer env 'keyword_package))) 0 1)))))))

(defun native_mvb_names_p (context names)
  (declare (type (ptr native_compile_context) context) (type usize names) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (if (= (ast_list_p parser names) 0) 0
        (let ((first (ast_first parser names)))
          (if (= (native_mvb_name_p context first) 0) 0
              (let ((second (ast_next parser first)))
                (if (= (native_mvb_name_p context second) 0) 0
                    (if (= (ast_next parser second) 0)
                        (if (= (ast_same_name_p parser source first second) 1) 0 1) 0))))))))

(defun native_mvb_second_hir (context source)
  (declare (type (ptr native_compile_context) context) (type usize source) (returns usize))
  (let ((arena (deref (field-pointer context 'hir)))
        (function (native_runtime_function_index context 21 0)))
    (if (= function 0) 0
        (let ((index (hir_new_scalar arena 1 1 0 0 0 source 2)))
          (if (= index 0) 0
              (let ((link (hir_new_scalar arena 17 0 index 0 0 source 2)))
                (if (= link 0) 0 (hir_new_scalar arena 7 0 link 0 function source 15))))))))

(defun native_mvb_binding (context name initializer previous)
  (declare (type (ptr native_compile_context) context)
           (type usize name initializer previous) (returns usize))
  (if (= initializer 0) 0
      (let ((arena (deref (field-pointer context 'hir)))
            (slot (wrap+ (deref (field-pointer context 'local_count)) 1)))
        (store (field-pointer context 'local_count) slot)
        (hir_copy_type arena
         (hir_new_scalar arena 14 (wrap-cast u64 slot) initializer 0 previous name 15) initializer))))

(defun native_mvb_bindings (context source names initializer outer depth)
  (declare (type (ptr native_compile_context) context)
           (type usize source names initializer outer depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((first (native_mvb_binding context (ast_first parser names)
                  (analyze_scalar_expected context initializer 15 (wrap+ depth 1)) outer)))
      (if (= first 0) 0
          (native_mvb_binding context (ast_next parser (ast_first parser names))
                              (native_mvb_second_hir context source) first)))))

(defun native_mvb_body (context source names initializer depth)
  (declare (type (ptr native_compile_context) context)
           (type usize source names initializer depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (outer (deref (field-pointer context 'active_binding))))
    (let ((bindings (native_mvb_bindings context source names initializer outer depth)))
      (if (= bindings 0) 0
          (progn
            (store (field-pointer context 'active_binding) bindings)
            (let ((result (analyze_scalar_sequence_from context (ast_next parser initializer)
                           0 source (wrap+ depth 1))))
              (store (field-pointer context 'active_binding) outer)
              (if (= result 0) 0 (wrap_let_bindings context bindings outer result source))))))))

(defun analyze_multiple_value_bind (context body depth)
  (declare (type (ptr native_compile_context) context) (type usize body depth) (returns usize))
  (if (= (deref (field-pointer context 'profile)) 1)
      (let ((parser (deref (field-pointer context 'parser))))
        (let ((names (ast_next parser (ast_first parser body))))
          (if (= (native_mvb_names_p context names) 0) 0
              (let ((initializer (ast_next parser names)))
                (if (= (native_values_form_p context initializer) 0) 0
                    (if (= (ast_next parser initializer) 0) 0
                        (native_mvb_body context body names initializer depth))))))) 0))
