;; Source memory analysis uses declared pointee types and layout metadata.
;; All pointer operands are explicit; integer literals never imply pointers.

(defun analyze_source_expected (context body expected pointee depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body pointee depth)
           (type u32 expected) (returns usize))
  (let ((previous (deref (field-pointer context 'expected_type)))
        (previous_pointee (deref (field-pointer context 'expected_pointee))))
    (store (field-pointer context 'expected_type) expected)
    (store (field-pointer context 'expected_pointee) pointee)
    (let ((result (analyze_scalar_expr context body depth)))
      (store (field-pointer context 'expected_type) previous)
      (store (field-pointer context 'expected_pointee) previous_pointee)
      result)))

(defun analyze_pointer_operand (context operand depth)
  (declare (type (ptr native_compile_context) context)
           (type usize operand depth) (returns usize))
  (let ((reference (analyze_scalar_expected context operand 0 (wrap+ depth 1))))
    (if (= reference 0)
        0
        (if (= (hir_scalar_code (deref (field-pointer context 'hir)) reference) 11)
            reference 0))))

(defun analyze_pointer_cast (context body kind depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (type u32 kind) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (arena (deref (field-pointer context 'hir))))
    (let ((type (ast_next parser (ast_first parser body))))
      (if (= (call_shape_from_p parser type 2) 0)
          0
          (let ((pointee (source_type_pointee
                         (deref (field-pointer context 'signatures)) type)))
            (if (= pointee 0)
                0
                (let ((operand (ast_next parser type)))
                  (let ((child (if (= kind 21)
                                   (analyze_scalar_expected context operand 2 (wrap+ depth 1))
                                   (analyze_pointer_operand context operand depth))))
                    (if (= child 0) 0
                        (hir_with_pointee arena
                         (hir_new_scalar arena kind 0 child 0 0 body 11) pointee))))))))))

(defun analyze_pointer_add (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (arena (deref (field-pointer context 'hir))))
    (let ((first (ast_next parser (ast_first parser body))))
      (if (= (call_shape_from_p parser first 2) 0)
          0
          (let ((pointer (analyze_pointer_operand context first depth)))
            (if (= pointer 0) 0
                (let ((offset (analyze_scalar_expected context (ast_next parser first)
                                                       10 (wrap+ depth 1))))
                  (if (= offset 0) 0
                      (let ((size (source_type_size context (hir_pointee arena pointer))))
                        (if (= size 0) 0
                            (hir_copy_type arena
                             (hir_new_scalar arena 27 (wrap-cast u64 size)
                                             pointer offset 0 body 11) pointer)))))))))))

(defun source_quoted_name (parser source form)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize form) (returns usize))
  (if (= form 0) 0
      (let ((node (parser_node parser form)))
        (if (= (deref (field-pointer node 'kind)) 3)
            (ast_first parser form)
            (if (= (ast_list_p parser form) 0) 0
                (let ((head (ast_first parser form)))
                  (if (= (ast_word_p parser source head #x65746f7571 5) 0) 0
                      (let ((name (ast_next parser head)))
                        (if (= (call_shape_from_p parser name 1) 0) 0 name)))))))))

(defun analyze_field_pointer (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (arena (deref (field-pointer context 'hir))))
    (let ((first (ast_next parser (ast_first parser body))))
      (if (= (call_shape_from_p parser first 2) 0) 0
          (let ((pointer (analyze_pointer_operand context first depth)))
            (if (= pointer 0) 0
                (let ((name (source_quoted_name parser
                             (deref (field-pointer context 'source))
                             (ast_next parser first))))
                  (let ((index (source_find_field context (hir_pointee arena pointer) name)))
                    (if (= index 0) 0
                        (let ((field (native_field_at (source_layouts context)
                                                       (wrap- index 1))))
                          (hir_with_pointee arena
                           (hir_new_scalar arena 23
                            (wrap-cast u64 (deref (field-pointer field 'offset)))
                            pointer 0 index body 11)
                           (deref (field-pointer field 'type_ast)))))))))))))

(defun analyze_memory_access (context body kind depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (type u32 kind) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((first (ast_next parser (ast_first parser body))))
      (if (= (call_shape_from_p parser first (if (= kind 24) 1 2)) 0) 0
          (let ((pointer (analyze_pointer_operand context first depth)))
            (if (= pointer 0) 0
                (analyze_typed_memory context body kind pointer
                                      (ast_next parser first) depth)))))))

(defun analyze_typed_memory (context body kind pointer value_ast depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body pointer value_ast depth)
           (type u32 kind) (returns usize))
  (let ((arena (deref (field-pointer context 'hir)))
        (signatures (deref (field-pointer context 'signatures))))
    (let ((type (hir_pointee arena pointer)))
      (let ((code (scalar_type_code signatures type))
            (pointee (source_type_pointee signatures type))
            (size (source_type_size context type)))
        (if (= (source_valid_code_p code) 0) 0
            (let ((value (if (= kind 24) (wrap-cast usize 0)
                            (analyze_source_expected context value_ast code pointee
                                                     (wrap+ depth 1)))))
              (if (= kind 25)
                  (if (= value 0) 0
                      (hir_with_pointee arena
                       (hir_new_scalar arena kind (wrap-cast u64 size)
                                       pointer value 0 body code) pointee))
                  (hir_with_pointee arena
                   (hir_new_scalar arena kind (wrap-cast u64 size)
                                   pointer 0 0 body code) pointee))))))))

(defun analyze_loop_body (context first body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize first body depth) (returns usize))
  (let ((expected (deref (field-pointer context 'expected_type)))
        (pointee (deref (field-pointer context 'expected_pointee))))
    (store (field-pointer context 'expected_type) 0)
    (store (field-pointer context 'expected_pointee) 0)
    (let ((result (analyze_scalar_sequence_from context first 0 body (wrap+ depth 1))))
      (store (field-pointer context 'expected_type) expected)
      (store (field-pointer context 'expected_pointee) pointee)
      result)))

(defun analyze_while_expr (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (arena (deref (field-pointer context 'hir))))
    (let ((condition (ast_next parser (ast_first parser body))))
      (let ((first (ast_next parser condition)))
        (if (= first 0) 0
            (let ((test (analyze_scalar_expected context condition 0 (wrap+ depth 1))))
              (if (= test 0) 0
                  (if (= (hir_scalar_code arena test) 0)
                      (let ((value (analyze_loop_body context first body depth)))
                        (if (= value 0) 0
                            (hir_new_scalar arena 26 0 test value 0 body 0)))
                      0))))))))

(defun analyze_memory_operation (context body kind depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (type u32 kind) (returns usize))
  (cond
    ((= kind 21) (analyze_pointer_cast context body kind depth))
    ((= kind 22) (analyze_pointer_cast context body kind depth))
    ((= kind 23) (analyze_field_pointer context body depth))
    ((= kind 24) (analyze_memory_access context body kind depth))
    ((= kind 25) (analyze_memory_access context body kind depth))
    ((= kind 26) (analyze_while_expr context body depth))
    ((= kind 27) (analyze_pointer_add context body depth))
    (t 0)))

(defun source_memory_operation (parser source head)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize head) (returns u32))
  (cond
    ((= (ast_long_word_p parser source head #x6d6f72662d727470 #x737365726464612d 16) 1) 21)
    ((= (ast_word_p parser source head #x747361632d727470 8) 1) 22)
    ((= (ast_long_word_p parser source head #x6f702d646c656966 #x7265746e69 13) 1) 23)
    ((= (ast_word_p parser source head #x6665726564 5) 1) 24)
    ((= (ast_word_p parser source head #x65726f7473 5) 1) 25)
    ((= (ast_word_p parser source head #x656c696877 5) 1) 26)
    ((= (ast_word_p parser source head #x2b7265746e696f70 8) 1) 27)
    (t 0)))
