;; Expression dispatch and typed conditionals. Integer analysis and call
;; signatures live in separate modules; no target instructions appear here.

(include "hir_analyze_integer.lisp")
(include "hir_analyze_calls.lisp")
(include "hir_analyze_cond.lisp")
(include "hir_analyze_memory.lisp")

(defun comparison_kind (parser source head)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize head) (returns u32))
  (if (= (ast_word_p parser source head #x3d 1) 1)
      8
      (if (= (ast_word_p parser source head #x3c 1) 1) 9 0)))

(defun analyze_scalar_expected (context body expected depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth)
           (type u32 expected) (returns usize))
  (analyze_source_expected context body expected 0 depth))

(defun analyze_bool_expr (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((result (analyze_scalar_expected context body 0 depth)))
    (if (= result 0)
        0
        (let ((arena (deref (field-pointer context 'hir))))
          (if (= (hir_child_type_p arena result 2) 1)
              result
              (hir_new_scalar arena 20 0 result 0 0 body 0))))))

(defun analyze_if_parts (context body condition then_ast else_ast depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body condition then_ast else_ast depth) (returns usize))
  (let ((arena (deref (field-pointer context 'hir))))
    (let ((test (analyze_bool_expr context condition (wrap+ depth 1))))
      (if (= test 0)
          0
          (let ((then_value (analyze_scalar_expr context then_ast
                                                (wrap+ depth 1))))
            (if (= then_value 0)
                0
                (let ((code (hir_scalar_code arena then_value)))
                  (let ((else_value (analyze_source_expected
                                     context else_ast code (hir_pointee arena then_value)
                                     (wrap+ depth 1))))
                    (if (= else_value 0)
                        0
                        (hir_copy_type arena
                         (hir_new_scalar arena 10 0 test then_value else_value
                                         body code) then_value))))))))))

(defun analyze_if_expr (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((condition (ast_next parser (ast_first parser body))))
      (if (= (call_shape_from_p parser condition 3) 0)
          0
          (let ((then_ast (ast_next parser condition)))
            (analyze_if_parts context body condition then_ast
                              (ast_next parser then_ast) depth))))))

(defun analyze_scalar_operator (context body head depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body head depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (let ((comparison (comparison_kind parser source head)))
      (if (< 0 comparison)
          (hir_from_binary_kind context body comparison depth)
          (let ((operation (binary_operation parser source head)))
            (if (= operation 0)
                (hir_from_call context body depth)
                (hir_from_binary context body operation depth)))))))

(defun analyze_scalar_list (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (let ((head (ast_first parser body)))
      (cond
        ((= (ast_word_p parser source head #x6669 2) 1)
         (analyze_if_expr context body depth))
        ((= (ast_word_p parser source head #x6e676f7270 5) 1)
         (analyze_progn_expr context body depth))
        ((= (ast_word_p parser source head #x74656c 3) 1)
         (analyze_let_expr context body depth))
        ((= (ast_word_p parser source head #x646e6f63 4) 1)
         (analyze_cond_expr context body depth))
        ((= (ast_long_word_p parser source head #x7361632d70617277 #x74 9) 1)
         (hir_from_cast context body depth))
        (t (let ((memory (source_memory_operation parser source head)))
             (if (= memory 0)
                 (analyze_scalar_operator context body head depth)
                 (analyze_memory_operation context body memory depth))))))))

(defun analyze_scalar_form (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((kind (deref (field-pointer (parser_node parser body) 'kind))))
      (cond
        ((= kind 8) (hir_from_atom context body))
        ((= kind 1) (analyze_scalar_list context body depth))
        (t 0)))))

(defun analyze_scalar_expr (context body depth)
  (declare (type (ptr native_compile_context) context)
           (type usize body depth) (returns usize))
  (if (< 128 depth)
      0
      (if (= body 0)
          0
          (let ((result (analyze_scalar_form context body depth)))
            (if (= result 0)
                0
                (let ((expected (deref (field-pointer context 'expected_type))))
                  (if (= expected 0)
                      result
                      (if (= (hir_source_same_p context result expected
                                                (deref (field-pointer context 'expected_pointee))) 1)
                          result 0))))))))
