;; Integer atoms, arithmetic, and explicit casts. Source types are retained
;; on each HIR node even though integer storage uses a 64-bit word.

(defun hir_from_literal (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (returns usize))
  (let ((integer (deref (field-pointer context 'integer))))
    (let ((code (scalar_literal_code
                 (deref (field-pointer context 'expected_type)) integer)))
      (if (= (scalar_literal_valid_p code integer) 0)
          0
          (hir_new_scalar (deref (field-pointer context 'hir))
                          1 (scalar_literal_bits integer) 0 0 0 body code)))))

(defun hir_from_variable (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (returns usize))
  (let ((arena (deref (field-pointer context 'hir))))
    (let ((binding (hir_find_local
                    context body
                    (deref (field-pointer context 'active_binding)))))
      (if (< 0 binding)
          (hir_copy_type arena
           (hir_new_scalar arena 15 0 0 0 binding body
                           (hir_scalar_code arena binding)) binding)
          (let ((index (parameter_index context body)))
            (if (= index 0)
                0
                (hir_with_pointee arena
                 (hir_new_scalar arena 2 (wrap-cast u64 index) 0 0 0 body
                                 (scalar_current_parameter_code context index))
                 (scalar_signature_parameter_pointee
                  context (deref (field-pointer context 'current_signature))
                  (wrap- index 1)))))))))

(defun hir_integer_atom_p (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (returns c-int))
  (scalar_integer_atom_p
   (deref (field-pointer context 'parser))
   (deref (field-pointer context 'source)) body
   (deref (field-pointer context 'integer))))

(defun hir_from_atom (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source)))
        (arena (deref (field-pointer context 'hir))))
    (cond
      ((= (ast_word_p parser source body #x74 1) 1)
       (hir_new_scalar arena 19 1 0 0 0 body 0))
      ((= (ast_word_p parser source body #x6c696e 3) 1)
       (hir_new_scalar arena 19 0 0 0 0 body 0))
      ((= (hir_integer_atom_p context body) 1) (hir_from_literal context body))
      (t (hir_from_variable context body)))))

(defun hir_arithmetic_kind (operation)
  (declare (type u8 operation) (returns u32))
  (cond
    ((= operation 43) 4)
    ((= operation 45) 5)
    ((= operation 42) 6)
    ((= operation 38) 11)
    ((= operation 94) 12)
    (t 0)))

(defun hir_finish_binary (context body kind left right)
  (declare (type (ptr native_compile_context) context)
           (type usize body left right)
           (type u32 kind) (returns usize))
  (let ((arena (deref (field-pointer context 'hir))))
    (let ((code (hir_scalar_code arena left)))
      (if (= code (hir_scalar_code arena right))
          (if (= (scalar_binary_code_p code (if (= kind 12) 1 0)) 0)
              0
              (hir_new_scalar arena kind 0 left right 0 body
                              (if (= kind 8) 0 (if (= kind 9) 0 code))))
          0))))

(defun hir_binary_left_first (context body kind first second depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body first second depth)
           (type u32 kind) (returns usize))
  (let ((left (analyze_scalar_expr context first (wrap+ depth 1))))
    (if (= left 0)
        0
        (let ((right (analyze_scalar_expected
                      context second
                      (hir_scalar_code (deref (field-pointer context 'hir)) left)
                      (wrap+ depth 1))))
          (if (= right 0) 0 (hir_finish_binary context body kind left right))))))

(defun hir_binary_right_first (context body kind first second depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body first second depth)
           (type u32 kind) (returns usize))
  (let ((right (analyze_scalar_expr context second (wrap+ depth 1))))
    (if (= right 0)
        0
        (let ((left (analyze_scalar_expected
                     context first
                     (hir_scalar_code (deref (field-pointer context 'hir)) right)
                     (wrap+ depth 1))))
          (if (= left 0) 0 (hir_finish_binary context body kind left right))))))

(defun hir_binary_operands (context body kind depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (type u32 kind) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((first (ast_next parser (ast_first parser body))))
      (let ((second (ast_next parser first)))
        (if (= (hir_integer_atom_p context first) 1)
            (if (= (hir_integer_atom_p context second) 0)
                (hir_binary_right_first context body kind first second depth)
                (hir_binary_left_first context body kind first second depth))
            (hir_binary_left_first context body kind first second depth))))))

(defun hir_from_binary_kind (context body kind depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (type u32 kind) (returns usize))
  (if (= (binary_parts_p (deref (field-pointer context 'parser)) body) 0)
      0
      (hir_binary_operands context body kind depth)))

(defun hir_from_binary (context body operation depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (type u8 operation) (returns usize))
  (hir_from_binary_kind context body (hir_arithmetic_kind operation) depth))

(defun hir_from_cast_operand (context body type operand depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body operand depth)
           (type u32 type) (returns usize))
  (let ((child (analyze_scalar_expected context operand 0 (wrap+ depth 1))))
    (if (= child 0)
        0
        (if (= (scalar_valid_code_p
                (hir_scalar_code (deref (field-pointer context 'hir)) child)) 0)
            0
            (hir_new_scalar (deref (field-pointer context 'hir))
                            18 0 child 0 0 body type)))))

(defun hir_from_cast (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((type_ast (ast_next parser (ast_first parser body))))
      (let ((operand (ast_next parser type_ast))
            (type (scalar_type_code
                   (deref (field-pointer context 'signatures)) type_ast)))
        (if (= (scalar_valid_code_p type) 0)
            0
            (if (= operand 0)
                0
                (if (= (ast_next parser operand) 0)
                    (hir_from_cast_operand context body type operand depth)
                    0)))))))
