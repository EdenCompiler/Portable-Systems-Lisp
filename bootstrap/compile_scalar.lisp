(include "frontend/parser.lisp")
(include "frontend/atoms.lisp")
(include "object/elf64_multi.lisp")
(include "frontend/signatures.lisp")
(include "ir/hir.lisp")
(include "ir/ssa.lisp")
(include "ir/lir.lisp")
(include "backend/x86_expr.lisp")
(include "backend/x86_calls.lisp")
(include "backend/x86_control.lisp")
(include "backend/x86_memory.lisp")

;; First native source-to-object path. Signatures are collected before bodies;
;; typed HIR and x86 call fixups support forward calls and recursion.

(defcstruct native_compile_context
  (parser (ptr psl_parser))
  (source (ptr u8))
  (integer (ptr psl_parsed_integer))
  (hir (ptr native_hir_arena))
  (code (ptr byte_buffer))
  (fixups (ptr native_fixup_arena))
  (functions (ptr native_function))
  (signatures (ptr native_signature_context))
  (prior_count usize)
  (current_arity usize)
  (current_signature (ptr native_signature))
  (expected_type u32)
  (active_binding usize)
  (local_count usize)
  (expected_pointee usize)
  (ssa (ptr native_ssa_arena))
  (bindings (ptr usize))
  (lir (ptr native_lir_arena))
  (labels (ptr usize))
  (jumps (ptr native_fixup_arena)))

(include "frontend/scalar_syntax.lisp")
(include "frontend/scalar_types.lisp")
(include "frontend/pointer_types.lisp")
(include "ir/ir_verify_type_helpers.lisp")
(include "frontend/scalar_resolve.lisp")

(defun configure_scalar_signature (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (returns c-int))
  (store (field-pointer context 'current_arity)
         (deref (field-pointer signature 'arity)))
  (store (field-pointer context 'current_signature) signature)
  (store (field-pointer context 'expected_type)
         (scalar_signature_type_code context signature))
  (store (field-pointer context 'expected_pointee)
         (source_type_pointee (deref (field-pointer context 'signatures))
                              (deref (field-pointer signature 'result_type))))
  1)

(defun record_scalar_signature (context signature function)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type (ptr native_function) function)
           (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (let ((node (parser_node parser
                             (deref (field-pointer signature 'name)))))
      (if (= (deref (field-pointer node 'kind)) 8)
          (if (= (scalar_function_name_p
                  source node (deref (field-pointer signature 'exported))) 1)
              (progn
                (store (field-pointer function 'name)
                       (pointer+ source
                                 (wrap-cast isize
                                            (deref (field-pointer node
                                                                  'start)))))
                (store (field-pointer function 'name_length)
                       (deref (field-pointer node 'length)))
                (store (field-pointer function 'arity)
                       (deref (field-pointer signature 'arity)))
                (store (field-pointer function 'exported)
                       (wrap-cast usize
                                  (deref (field-pointer signature
                                                        'exported))))
                1)
              0)
          0))))

(defun scalar_function_name_p (source node exported)
  (declare (type (ptr u8) source)
           (type (ptr psl_ast_node) node)
           (type u8 exported)
           (returns c-int))
  (let ((start (deref (field-pointer node 'start)))
        (length (deref (field-pointer node 'length))))
    (if (= (simple_source_name_p source start length) 0)
        0
        (if (= exported 1)
            (simple_export_name_p source start length)
            1))))

(defun predeclare_scalar_form (context signature function)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type (ptr native_function) function)
           (returns c-int)
           (c-export :c))
  (if (= (scalar_signature_p context signature) 0)
      0
      (progn
        (configure_scalar_signature context signature)
        (record_scalar_signature context signature function))))

(defun finish_scalar_function (context start function)
  (declare (type (ptr native_compile_context) context)
           (type usize start)
           (type (ptr native_function) function)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (store (field-pointer function 'offset) start)
    (store (field-pointer function 'size)
           (wrap- (deref (field-pointer code 'length)) start))
    1))

(include "frontend/hir_analyze_scalar.lisp")
(include "frontend/hir_analyze_lexical.lisp")
(include "ir/hir_verify_types.lisp")
(include "ir/ssa_lower.lisp")
(include "ir/ssa_lower_control.lisp")
(include "ir/ssa_verify.lisp")
(include "ir/lir_lower.lisp")
(include "ir/lir_verify.lisp")
(include "backend/lir_emit_x86.lisp")

(defun reset_scalar_function (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns c-int))
  (let ((arena (deref (field-pointer context 'hir))))
    (configure_scalar_signature context signature)
    (store (field-pointer arena 'count) 0)
    (store (field-pointer arena 'error) 0)
    (store (field-pointer context 'active_binding) 0)
    (store (field-pointer context 'local_count) 0)
    1))

(defun analyze_scalar_function (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns usize))
  (reset_scalar_function context signature)
  (let ((body (deref (field-pointer signature 'body))))
    (analyze_scalar_sequence_from context body 0 body 0)))

(defun lower_scalar_function (context expression)
  (declare (type (ptr native_compile_context) context)
           (type usize expression) (returns c-int))
  (if (= (ssa_lower_function context expression) 0) 0
      (if (= (ssa_verify_function context) 0) 0
          (if (= (lir_lower_function context) 0) 0
              (lir_verify_function context)))))

(defun compile_scalar_form (context signature function)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type (ptr native_function) function)
           (returns c-int) (c-export :c))
  (if (= (scalar_signature_p context signature) 0)
      0
      (let ((start (deref (field-pointer
                           (deref (field-pointer context 'code)) 'length))))
        (let ((expression (analyze_scalar_function context signature)))
          (if (= expression 0)
              0
              (if (= (hir_verify_typed_function context expression) 0)
                  0
                  (if (= (lower_scalar_function context expression) 0) 0
                      (if (= (emit_lir_x86_function context) 0) 0
                          (finish_scalar_function context start function)))))))))
