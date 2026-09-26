;; Typed integer lexical bindings and sequential bodies for the native slice.
;; Binding initializers are analyzed in the outer environment, as in CL LET.

(defun hir_find_local (context name binding)
  (declare (type (ptr native_compile_context) context)
           (type usize name binding)
           (returns usize))
  (if (= binding 0)
      0
      (let ((arena (deref (field-pointer context 'hir)))
            (parser (deref (field-pointer context 'parser)))
            (source (deref (field-pointer context 'source))))
        (let ((node (hir_node_at arena binding)))
          (if (= (ast_same_name_p
                  parser source name
                  (deref (field-pointer node 'source))) 1)
              binding
              (hir_find_local context name
                              (deref (field-pointer node 'target))))))))

(defun hir_binding_duplicate_p (context name binding outer)
  (declare (type (ptr native_compile_context) context)
           (type usize name binding outer)
           (returns c-int))
  (if (= binding outer)
      0
      (let ((arena (deref (field-pointer context 'hir)))
            (parser (deref (field-pointer context 'parser)))
            (source (deref (field-pointer context 'source))))
        (let ((node (hir_node_at arena binding)))
          (if (= (ast_same_name_p parser source name
                                  (deref (field-pointer node 'source))) 1)
              1
              (hir_binding_duplicate_p
               context name (deref (field-pointer node 'target)) outer))))))

(defun analyze_scalar_sequence_from (context next current source depth)
  (declare (type (ptr native_compile_context) context)
           (type usize next current source depth)
           (returns usize))
  (if (< 128 depth)
      0
      (if (= next 0)
          current
          (let ((parser (deref (field-pointer context 'parser)))
                (arena (deref (field-pointer context 'hir))))
            (let ((part (analyze_source_expected
                         context next
                         (if (= (ast_next parser next) 0)
                             (deref (field-pointer context 'expected_type))
                             0)
                         (if (= (ast_next parser next) 0)
                             (deref (field-pointer context 'expected_pointee))
                             (wrap-cast usize 0))
                         (wrap+ depth 1))))
              (if (= part 0)
                  0
                  (let ((result (if (= current 0)
                                    part
                                    (hir_copy_type arena
                                     (hir_new_scalar arena 13 0 current part 0
                                                     source
                                                     (hir_scalar_code arena part)) part))))
                    (if (= result 0)
                        0
                        (analyze_scalar_sequence_from
                         context (ast_next parser next) result source
                         (wrap+ depth 1))))))))))

(defun analyze_progn_expr (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((first (ast_next parser (ast_first parser body))))
      (if (= first 0)
          0
          (analyze_scalar_sequence_from context first 0 body depth)))))

(defun lexical_binding_name (context binding)
  (declare (type (ptr native_compile_context) context)
           (type usize binding)
           (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (if (= (ast_list_p parser binding) 0)
        0
        (let ((name (ast_first parser binding)))
          (if (= (ast_variable_name_p parser source name) 0)
              0
              (let ((initializer (ast_next parser name)))
                (if (= initializer 0)
                    0
                    (if (= (ast_next parser initializer) 0) name 0))))))))

(defun analyze_one_binding (context binding previous outer depth)
  (declare (type (ptr native_compile_context) context)
           (type usize binding previous outer depth)
           (returns usize))
  (let ((name (lexical_binding_name context binding)))
    (if (= name 0)
        0
        (if (= (hir_binding_duplicate_p context name previous outer) 1)
            0
            (let ((parser (deref (field-pointer context 'parser)))
                  (arena (deref (field-pointer context 'hir))))
              (let ((initializer
                     (analyze_scalar_expected context (ast_next parser name)
                                              0 (wrap+ depth 1))))
                (if (= initializer 0)
                    0
                    (let ((slot (wrap+ (deref (field-pointer context
                                                               'local_count))
                                       1)))
                      (store (field-pointer context 'local_count) slot)
                      (hir_copy_type arena
                       (hir_new_scalar arena 14 (wrap-cast u64 slot)
                                       initializer 0 previous name
                                       (hir_scalar_code arena initializer)) initializer)))))))))

(defun analyze_let_bindings (context next previous outer depth)
  (declare (type (ptr native_compile_context) context)
           (type usize next previous outer depth)
           (returns usize))
  (if (< 128 depth)
      0
      (if (= next 0)
          previous
          (let ((parser (deref (field-pointer context 'parser))))
            (let ((binding (analyze_one_binding context next previous outer
                                                depth)))
              (if (= binding 0)
                  0
                  (analyze_let_bindings context (ast_next parser next)
                                        binding outer (wrap+ depth 1))))))))

(defun wrap_let_bindings (context binding outer body source)
  (declare (type (ptr native_compile_context) context)
           (type usize binding outer body source)
           (returns usize))
  (if (= binding outer)
      body
      (let ((arena (deref (field-pointer context 'hir))))
        (let ((previous (deref (field-pointer
                               (hir_node_at arena binding) 'target))))
          (let ((wrapped (hir_copy_type arena
                          (hir_new_scalar arena 16 0 binding body 0 source
                                          (hir_scalar_code arena body)) body)))
            (if (= wrapped 0)
                0
                (wrap_let_bindings context previous outer wrapped
                                   source)))))))

(defun let_bindings_failed_p (first last)
  (declare (type usize first last) (returns c-int))
  (if (= first 0) 0 (if (= last 0) 1 0)))

(defun let_body_first (parser body)
  (declare (type (ptr psl_parser) parser)
           (type usize body)
           (returns usize))
  (ast_next parser (ast_next parser (ast_first parser body))))

(defun analyze_let_body (context body first_binding outer depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body first_binding outer depth)
           (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((last (if (= first_binding 0)
                    outer
                    (analyze_let_bindings context first_binding outer outer
                                          depth))))
      (if (= (let_bindings_failed_p first_binding last) 1)
          0
          (progn
            (store (field-pointer context 'active_binding) last)
            (let ((result (analyze_scalar_sequence_from
                           context (let_body_first parser body)
                           0 body depth)))
              (store (field-pointer context 'active_binding) outer)
              (if (= result 0)
                  0
                  (wrap_let_bindings context last outer result body))))))))

(defun analyze_let_expr (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((bindings (ast_next parser (ast_first parser body))))
      (if (= (ast_list_p parser bindings) 0)
          0
          (if (= (ast_next parser bindings) 0)
              0
              (analyze_let_body
               context body (ast_first parser bindings)
               (deref (field-pointer context 'active_binding))
               depth))))))
