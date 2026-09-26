;; Raw pointer source types retain the pointee syntax tree. Type equality
;; compares declarations structurally, so separate (ptr u8) forms agree.

(defun source_layouts (context)
  (declare (type (ptr native_compile_context) context)
           (returns (ptr native_layout_context)))
  (deref (field-pointer (deref (field-pointer context 'signatures)) 'layouts)))

(defun source_valid_code_p (code)
  (declare (type u32 code) (returns c-int))
  (if (= code 11) 1 (scalar_valid_code_p code)))

(defun source_type_pointee (signatures type)
  (declare (type (ptr native_signature_context) signatures)
           (type usize type) (returns usize))
  (let ((layouts (deref (field-pointer signatures 'layouts))))
    (let ((shape (deref (field-pointer layouts 'scratch))))
      (if (= (native_resolve_pointer_type layouts type shape) 0)
          0
          (deref (field-pointer shape 'pointee))))))

(defun source_type_size (context type)
  (declare (type (ptr native_compile_context) context)
           (type usize type) (returns usize))
  (let ((layouts (source_layouts context)))
    (let ((shape (deref (field-pointer layouts 'scratch))))
      (if (= (native_resolve_type layouts type shape) 0)
          0
          (deref (field-pointer shape 'size))))))

(defun source_type_reference_p (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (if (= reference 0) 0
      (if (< (deref (field-pointer (deref (field-pointer context 'parser)) 'count))
             reference) 0 1)))

(defun source_resolved_types_equal_p (context left right depth)
  (declare (type (ptr native_compile_context) context)
           (type usize left right depth) (returns c-int))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (let ((a (scalar_type_code signatures left))
          (b (scalar_type_code signatures right)))
      (if (= a b)
          (cond
            ((= a 11)
             (source_ast_type_equal_p context
                                     (source_type_pointee signatures left)
                                     (source_type_pointee signatures right)
                                     (wrap+ depth 1)))
            ((= a 0) (layout_names_equal_p (source_layouts context) left right))
            (t 1))
          0))))

(defun source_ast_type_equal_p (context left right depth)
  (declare (type (ptr native_compile_context) context)
           (type usize left right depth) (returns c-int))
  (if (< 128 depth) 0
      (if (= (source_type_reference_p context left) 0) 0
          (if (= (source_type_reference_p context right) 0) 0
              (source_resolved_types_equal_p context left right depth)))))

(defun source_types_equal_p (context left_code left_pointee right_code right_pointee)
  (declare (type (ptr native_compile_context) context)
           (type u32 left_code right_code)
           (type usize left_pointee right_pointee) (returns c-int))
  (if (= left_code right_code)
      (if (= left_code 11)
          (source_ast_type_equal_p context left_pointee right_pointee 0)
          (if (= left_pointee 0) (if (= right_pointee 0) 1 0) 0))
      0))

(defun hir_source_same_p (context reference code pointee)
  (declare (type (ptr native_compile_context) context)
           (type usize reference pointee)
           (type u32 code) (returns c-int))
  (let ((arena (deref (field-pointer context 'hir))))
    (source_types_equal_p context (hir_scalar_code arena reference)
                          (hir_pointee arena reference) code pointee)))

(defun hir_source_matches_node_p (context reference node)
  (declare (type (ptr native_compile_context) context)
           (type usize reference)
           (type (ptr native_hir_node) node) (returns c-int))
  (hir_source_same_p context reference
                     (deref (field-pointer node 'scalar_code))
                     (deref (field-pointer node 'pointee))))

(defun scalar_signature_parameter_pointee (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize index) (returns usize))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (let ((parameter (native_parameter_at
                      signatures (wrap+ (deref (field-pointer signature 'first_parameter))
                                         index))))
      (source_type_pointee signatures (deref (field-pointer parameter 'type_ast))))))

(defun scalar_signature_result_pointee (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns usize))
  (source_type_pointee (deref (field-pointer context 'signatures))
                       (deref (field-pointer signature 'result_type))))

(defun source_find_field_from (layouts name first count)
  (declare (type (ptr native_layout_context) layouts)
           (type usize name first count) (returns usize))
  (if (= count 0)
      0
      (if (= (layout_names_equal_p layouts name
               (deref (field-pointer (native_field_at layouts first) 'name))) 1)
          (wrap+ first 1)
          (source_find_field_from layouts name (wrap+ first 1) (wrap- count 1)))))

(defun source_find_field (context pointee name)
  (declare (type (ptr native_compile_context) context)
           (type usize pointee name) (returns usize))
  (let ((layouts (source_layouts context)))
    (let ((index (native_find_layout layouts pointee)))
      (if (= index 0)
          0
          (let ((layout (native_layout_at layouts (wrap- index 1))))
            (source_find_field_from layouts name
                                    (deref (field-pointer layout 'first))
                                    (deref (field-pointer layout 'count))))))))
