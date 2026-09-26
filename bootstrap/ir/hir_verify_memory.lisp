;; Typed memory verification checks relationships independently of analysis.
;; The structural pass has already validated all HIR child references.

(defun hir_pointer_child_p (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (let ((node (hir_node_at (deref (field-pointer context 'hir)) reference)))
    (if (= (deref (field-pointer node 'scalar_code)) 11)
        (hir_source_type_p context node)
        0)))

(defun hir_verify_word_truth (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((child (deref (field-pointer node 'left))))
    (if (= (source_valid_code_p
            (hir_scalar_code (deref (field-pointer context 'hir)) child)) 0) 0
        (hir_verify_scalar_tree context child (wrap+ depth 1)))))

(defun hir_verify_pointer_cast (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (if (= (deref (field-pointer node 'scalar_code)) 11)
      (let ((child (deref (field-pointer node 'left))))
        (if (= (deref (field-pointer node 'kind)) 21)
            (if (= (hir_scalar_same_p context child 2) 0) 0
                (hir_verify_scalar_tree context child (wrap+ depth 1)))
            (if (= (hir_pointer_child_p context child) 0) 0
                (hir_verify_scalar_tree context child (wrap+ depth 1)))))
      0))

(defun hir_verify_pointer_add (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((left (deref (field-pointer node 'left))))
    (if (= (hir_pointer_child_p context left) 0) 0
        (if (= (hir_source_matches_node_p context left node) 0) 0
            (if (= (hir_scalar_same_p context (deref (field-pointer node 'right)) 10) 0) 0
                (if (= (deref (field-pointer node 'value))
                       (wrap-cast u64 (source_type_size context
                                       (deref (field-pointer node 'pointee)))))
                    (hir_verify_scalar_pair context node depth)
                    0))))))

(defun hir_verify_field_metadata (context node field)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type (ptr native_layout_field) field) (returns c-int))
  (let ((left (deref (field-pointer node 'left)))
        (arena (deref (field-pointer context 'hir))))
    (if (= (deref (field-pointer node 'target))
           (source_find_field context (hir_pointee arena left)
                              (deref (field-pointer field 'name))))
        (if (= (deref (field-pointer node 'value))
               (wrap-cast u64 (deref (field-pointer field 'offset))))
            (source_ast_type_equal_p context (deref (field-pointer node 'pointee))
                                     (deref (field-pointer field 'type_ast)) 0)
            0)
        0)))

(defun hir_verify_field_pointer (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((index (deref (field-pointer node 'target)))
        (layouts (source_layouts context)))
    (if (= (deref (field-pointer node 'scalar_code)) 11)
        (if (< (deref (field-pointer layouts 'field_count)) index) 0
            (if (= (hir_pointer_child_p context (deref (field-pointer node 'left))) 0) 0
                (if (= (hir_verify_field_metadata context node
                         (native_field_at layouts (wrap- index 1))) 0) 0
                    (hir_verify_scalar_tree context (deref (field-pointer node 'left))
                                            (wrap+ depth 1)))))
        0)))

(defun hir_memory_result_p (context node type)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize type) (returns c-int))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (source_types_equal_p context (deref (field-pointer node 'scalar_code))
                          (deref (field-pointer node 'pointee))
                          (scalar_type_code signatures type)
                          (source_type_pointee signatures type))))

(defun hir_verify_memory_access (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((left (deref (field-pointer node 'left)))
        (arena (deref (field-pointer context 'hir))))
    (if (= (hir_pointer_child_p context left) 0) 0
        (let ((type (hir_pointee arena left)))
          (if (= (source_type_reference_p context type) 0) 0
              (if (= (hir_memory_result_p context node type) 0) 0
                  (if (= (deref (field-pointer node 'value))
                         (wrap-cast u64 (source_type_size context type)))
                      (if (= (deref (field-pointer node 'kind)) 24)
                          (hir_verify_scalar_tree context left (wrap+ depth 1))
                          (if (= (hir_source_matches_node_p
                                  context (deref (field-pointer node 'right)) node) 0) 0
                              (hir_verify_scalar_pair context node depth)))
                      0)))))))

(defun hir_verify_loop (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (if (= (hir_scalar_same_p context (deref (field-pointer node 'left)) 0) 0) 0
      (hir_verify_scalar_pair context node depth)))

(defun hir_verify_memory_kind (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns c-int))
  (let ((kind (deref (field-pointer node 'kind))))
    (cond
      ((= kind 21) (hir_verify_pointer_cast context node depth))
      ((= kind 22) (hir_verify_pointer_cast context node depth))
      ((= kind 23) (hir_verify_field_pointer context node depth))
      ((= kind 24) (hir_verify_memory_access context node depth))
      ((= kind 25) (hir_verify_memory_access context node depth))
      ((= kind 26) (hir_verify_loop context node depth))
      ((= kind 27) (hir_verify_pointer_add context node depth))
      (t 0))))
