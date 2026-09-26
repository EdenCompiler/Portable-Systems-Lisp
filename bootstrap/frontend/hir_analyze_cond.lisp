;; Native COND accepts test-and-body clauses. An exhausted clause list returns
;; NIL; a T clause supplies its body directly, as in host macro expansion.

(defun analyze_cond_if (context source predicate then_value else_value depth)
  (declare (type (ptr native_compile_context) context)
           (type usize source predicate then_value else_value depth)
           (returns usize))
  (let ((arena (deref (field-pointer context 'hir))))
    (let ((code (hir_scalar_code arena then_value)))
      (if (= (hir_source_same_p context else_value code
                                (hir_pointee arena then_value)) 1)
          (let ((test (analyze_bool_expr context predicate (wrap+ depth 1))))
            (if (= test 0)
                0
                (hir_copy_type arena
                 (hir_new_scalar arena 10 0 test then_value else_value source code)
                 then_value)))
          0))))

(defun analyze_cond_parts (context clause predicate first source depth)
  (declare (type (ptr native_compile_context) context)
           (type usize clause predicate first source depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (text (deref (field-pointer context 'source))))
    (let ((body (analyze_scalar_sequence_from context first 0 source
                                             (wrap+ depth 1))))
      (if (= body 0)
          0
          (if (= (ast_word_p parser text predicate #x74 1) 1)
              body
              (let ((tail (analyze_cond_from context (ast_next parser clause)
                                             source (wrap+ depth 1))))
                (if (= tail 0)
                    0
                    (analyze_cond_if context source predicate body tail depth))))))))

(defun analyze_cond_clause (context clause source depth)
  (declare (type (ptr native_compile_context) context)
           (type usize clause source depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (ast_list_p parser clause) 0)
        0
        (let ((predicate (ast_first parser clause)))
          (let ((first (ast_next parser predicate)))
            (if (= first 0)
                0
                (analyze_cond_parts context clause predicate first source depth)))))))

(defun analyze_cond_from (context clause source depth)
  (declare (type (ptr native_compile_context) context)
           (type usize clause source depth) (returns usize))
  (if (< 128 depth)
      0
      (if (= clause 0)
          (hir_new_scalar (deref (field-pointer context 'hir))
                          19 0 0 0 0 source 0)
          (analyze_cond_clause context clause source depth))))

(defun analyze_cond_expr (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (analyze_cond_from context (ast_next parser (ast_first parser body)) body depth)))
