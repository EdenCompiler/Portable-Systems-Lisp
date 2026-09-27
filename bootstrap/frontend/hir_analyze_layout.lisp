;; Layout queries are resolved to USIZE literals before HIR verification.
;; Quoted designators can name primitives, structures, or pointer types.

(defun analyze_layout_literal (context body value)
  (declare (type (ptr native_compile_context) context)
           (type usize body value) (returns usize))
  (hir_new_scalar (deref (field-pointer context 'hir))
                  1 (wrap-cast u64 value) 0 0 0 body 2))

(defun analyze_layout_size (context body type kind)
  (declare (type (ptr native_compile_context) context)
           (type usize body type) (type u32 kind) (returns usize))
  (let ((layouts (source_layouts context)))
    (let ((shape (deref (field-pointer layouts 'scratch))))
      (if (= (native_resolve_type layouts type shape) 0) 0
          (if (= (deref (field-pointer shape 'kind)) 4) 0
              (analyze_layout_literal context body
                (if (= kind 31) (deref (field-pointer shape 'size))
                    (deref (field-pointer shape 'alignment)))))))))

(defun analyze_layout_offset (context body type field_form)
  (declare (type (ptr native_compile_context) context)
           (type usize body type field_form) (returns usize))
  (let ((field (source_quoted_name (deref (field-pointer context 'parser))
                                  (deref (field-pointer context 'source)) field_form)))
    (if (= field 0) 0
        (let ((index (source_find_field context type field)))
          (if (= index 0) 0
              (analyze_layout_literal context body
                (deref (field-pointer (native_field_at (source_layouts context)
                                                        (wrap- index 1)) 'offset))))))))

(defun analyze_layout_query (context body kind)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (type u32 kind) (returns usize))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (let ((first (ast_next parser (ast_first parser body))))
      (if (= (call_shape_from_p parser first (if (= kind 33) 2 1)) 0) 0
          (let ((type (source_quoted_name parser source first)))
            (if (= type 0) 0
                (if (= kind 33)
                    (analyze_layout_offset context body type (ast_next parser first))
                    (analyze_layout_size context body type kind))))))))
