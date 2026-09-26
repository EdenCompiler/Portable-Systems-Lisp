;; Source-type verification runs after the structural and lexical HIR passes.
;; It checks every integer width, declared parameter, call signature, and cast.

(include "hir_verify_memory.lisp")

(defun hir_source_type_p (context node)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node) (returns c-int))
  (let ((code (deref (field-pointer node 'scalar_code)))
        (pointee (deref (field-pointer node 'pointee))))
    (if (= code 11)
        (if (= (deref (field-pointer node 'type_code)) 1)
            (if (= (source_type_reference_p context pointee) 0) 0
                (if (= (source_type_size context pointee) 0) 0 1))
            0)
        (if (= pointee 0)
            (if (= (deref (field-pointer node 'type_code)) 2)
                (if (= code 0) 1 0)
                (scalar_valid_code_p code))
            0))))

(defun hir_scalar_same_p (context reference code)
  (declare (type (ptr native_compile_context) context)
           (type usize reference)
           (type u32 code) (returns c-int))
  (if (= (hir_scalar_code (deref (field-pointer context 'hir)) reference) code)
      1 0))

(defun hir_verify_scalar_pair (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (if (= (hir_verify_scalar_tree context (deref (field-pointer node 'left))
                                (wrap+ depth 1)) 0)
      0
      (hir_verify_scalar_tree context (deref (field-pointer node 'right))
                              (wrap+ depth 1))))

(defun hir_verify_scalar_binary (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((code (deref (field-pointer node 'scalar_code))))
    (if (= (hir_scalar_same_p context (deref (field-pointer node 'left)) code) 0)
        0
        (if (= (hir_scalar_same_p context (deref (field-pointer node 'right)) code) 0)
            0
            (if (= (scalar_binary_code_p code
                                          (if (= (deref (field-pointer node 'kind)) 12)
                                              1 0)) 0)
                0
                (hir_verify_scalar_pair context node depth))))))

(defun hir_verify_scalar_comparison (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((code (hir_scalar_code (deref (field-pointer context 'hir))
                               (deref (field-pointer node 'left)))))
    (if (= (scalar_valid_code_p code) 0)
        0
        (if (= (hir_scalar_same_p context (deref (field-pointer node 'right)) code) 0)
            0
            (hir_verify_scalar_pair context node depth)))))

(defun hir_verify_scalar_result_pair (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (if (= (hir_source_matches_node_p context (deref (field-pointer node 'right)) node) 0)
      0
      (hir_verify_scalar_pair context node depth)))

(defun hir_verify_scalar_if (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((code (deref (field-pointer node 'scalar_code))))
    (if (= (hir_scalar_same_p context (deref (field-pointer node 'left)) 0) 0)
        0
        (if (= (hir_source_matches_node_p context (deref (field-pointer node 'target)) node) 0)
            0
            (if (= (hir_verify_scalar_result_pair context node depth) 0)
                0
                (hir_verify_scalar_tree context (deref (field-pointer node 'target))
                                        (wrap+ depth 1)))))))

(defun hir_verify_scalar_binding (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((child (deref (field-pointer node 'left))))
    (if (= (hir_source_matches_node_p context child node) 0)
        0
        (hir_verify_scalar_tree context child (wrap+ depth 1)))))

(defun hir_verify_scalar_cast (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((child (deref (field-pointer node 'left))))
    (if (= (scalar_valid_code_p
            (hir_scalar_code (deref (field-pointer context 'hir)) child)) 0)
        0
        (hir_verify_scalar_tree context child (wrap+ depth 1)))))

(defun hir_verify_scalar_arguments (context chain signature remaining depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize chain remaining depth) (returns c-int))
  (if (= remaining 0)
      (if (= chain 0) 1 0)
      (let ((link (hir_node_at (deref (field-pointer context 'hir)) chain)))
        (let ((code (scalar_signature_parameter_code
                     context signature (wrap- remaining 1))))
          (if (= (source_types_equal_p
                  context (deref (field-pointer link 'scalar_code))
                  (deref (field-pointer link 'pointee)) code
                  (scalar_signature_parameter_pointee context signature
                                                      (wrap- remaining 1))) 1)
              (if (= (hir_verify_scalar_binding context link depth) 0)
                  0
                  (hir_verify_scalar_arguments
                   context (deref (field-pointer link 'right)) signature
                   (wrap- remaining 1) (wrap+ depth 1)))
              0)))))

(defun hir_verify_scalar_call (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((signature
         (native_signature_at
          (deref (field-pointer context 'signatures))
          (wrap- (deref (field-pointer node 'target)) 1))))
    (if (= (source_types_equal_p
            context (deref (field-pointer node 'scalar_code))
            (deref (field-pointer node 'pointee))
            (scalar_signature_type_code context signature)
            (scalar_signature_result_pointee context signature)) 1)
        (hir_verify_scalar_arguments context (deref (field-pointer node 'left))
                                     signature
                                     (deref (field-pointer signature 'arity))
                                     depth)
        0)))

(defun hir_verify_scalar_kind (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((kind (deref (field-pointer node 'kind)))
        (code (deref (field-pointer node 'scalar_code))))
    (cond
      ((= kind 1) (scalar_word_valid_p code (deref (field-pointer node 'value))))
      ((= kind 2)
       (source_types_equal_p
        context code (deref (field-pointer node 'pointee))
        (scalar_current_parameter_code
         context (wrap-cast usize (deref (field-pointer node 'value))))
        (scalar_signature_parameter_pointee
         context (deref (field-pointer context 'current_signature))
         (wrap- (wrap-cast usize (deref (field-pointer node 'value))) 1))))
      ((= kind 7) (hir_verify_scalar_call context node depth))
      ((= kind 8) (hir_verify_scalar_comparison context node depth))
      ((= kind 9) (hir_verify_scalar_comparison context node depth))
      ((= kind 10) (hir_verify_scalar_if context node depth))
      ((= kind 13) (hir_verify_scalar_result_pair context node depth))
      ((= kind 14) (hir_verify_scalar_binding context node depth))
      ((= kind 15)
       (hir_source_matches_node_p context (deref (field-pointer node 'target)) node))
      ((= kind 16) (hir_verify_scalar_result_pair context node depth))
      ((= kind 18) (hir_verify_scalar_cast context node depth))
      ((= kind 19) (if (< 1 (deref (field-pointer node 'value))) 0 1))
      ((= kind 20) (hir_verify_word_truth context node depth))
      ((< 20 kind) (hir_verify_memory_kind context node depth))
      (t (hir_verify_scalar_binary context node depth)))))

;; The caller must first verify structural HIR references and lexical scope.
(defun hir_verify_scalar_tree (context reference depth)
  (declare (type (ptr native_compile_context) context)
           (type usize reference depth) (returns c-int) (c-export :c))
  (if (< 128 depth)
      0
      (let ((node (hir_node_at (deref (field-pointer context 'hir)) reference)))
        (if (= (hir_source_type_p context node) 0)
            0
            (hir_verify_scalar_kind context node depth)))))

(defun hir_verify_typed_function (context root)
  (declare (type (ptr native_compile_context) context)
           (type usize root) (returns c-int))
  (let ((arena (deref (field-pointer context 'hir))))
    (if (= (hir_verify_root arena root
                            (deref (field-pointer context 'functions))
                            (deref (field-pointer context 'prior_count))
                            (deref (field-pointer context 'current_arity))) 0)
        0
        (if (= (hir_source_same_p
                context root
                (scalar_signature_type_code
                 context (deref (field-pointer context 'current_signature)))
                (scalar_signature_result_pointee
                 context (deref (field-pointer context 'current_signature)))) 0)
            0
            (hir_verify_scalar_tree context root 0)))))
