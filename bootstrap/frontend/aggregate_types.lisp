;; By-value aggregate metadata retains the real source type reference.
;; The first native slice fits natural integer/pointer C records in one word.
;; ABI selection remains in the backend; no CPU register rules appear here.

(defun source_type_metadata (signatures type)
  (declare (type (ptr native_signature_context) signatures)
           (type usize type) (returns usize))
  (if (= (scalar_type_code signatures type) 16) (source_pointer_base type)
      (source_type_pointee signatures type)))

(defun source_aggregate_size_p (size)
  (declare (type usize size) (returns c-int))
  (if (if (= size 1) t (if (= size 2) t (if (= size 4) t (= size 8)))) 1 0))

(defun source_aggregate_field_type_p (context type depth)
  (declare (type (ptr native_compile_context) context)
           (type usize type depth) (returns c-int))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (let ((code (scalar_type_code signatures type)))
      (if (= (scalar_valid_code_p code) 1) 1
          (if (= code 11)
              (source_pointer_pointee_p context (source_type_pointee signatures type))
              (if (= code 16) (source_aggregate_at_depth_p context type depth) 0))))))

(defun source_aggregate_field_shape_p (context field offset depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_layout_field) field)
           (type usize offset depth) (returns c-int))
  (let ((layouts (source_layouts context))
        (type (deref (field-pointer field 'type_ast))))
    (let ((shape (deref (field-pointer layouts 'scratch))))
      (if (= (source_type_reference_p context type) 0) 0
          (if (= (native_resolve_type layouts type shape) 0) 0
              (if (= (deref (field-pointer field 'offset))
                     (layout_round_up offset (deref (field-pointer shape 'alignment))))
                  (if (= (deref (field-pointer field 'size)) (deref (field-pointer shape 'size)))
                      (if (= (deref (field-pointer field 'alignment)) (deref (field-pointer shape 'alignment)))
                          (source_aggregate_field_type_p context type (wrap+ depth 1)) 0) 0) 0))))))

(defun source_aggregate_fields_p (context layout first count offset alignment depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_layout) layout)
           (type usize first count offset alignment depth) (returns c-int))
  (if (= count 0)
      (if (= (layout_round_up offset alignment) (deref (field-pointer layout 'size)))
          (if (= alignment (deref (field-pointer layout 'alignment))) 1 0) 0)
      (let ((field (native_field_at (source_layouts context) first)))
        (if (= (source_aggregate_field_shape_p context field offset depth) 0) 0
            (let ((field_alignment (deref (field-pointer field 'alignment))))
              (source_aggregate_fields_p context layout (wrap+ first 1) (wrap- count 1)
               (wrap+ (deref (field-pointer field 'offset)) (deref (field-pointer field 'size)))
               (if (< alignment field_alignment) field_alignment alignment) depth))))))

(defun source_aggregate_layout_p (context layout depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_layout) layout) (type usize depth) (returns c-int))
  (let ((first (deref (field-pointer layout 'first)))
        (count (deref (field-pointer layout 'count)))
        (field_count (deref (field-pointer (source_layouts context) 'field_count))))
    (if (= (deref (field-pointer layout 'packed)) 0)
        (if (= (source_aggregate_size_p (deref (field-pointer layout 'size))) 0) 0
            (if (= count 0) 0
                (if (< field_count first) 0
                    (if (< (wrap- field_count first) count) 0
                        (source_aggregate_fields_p context layout first count 0 1 depth)))))
        0)))

(defun source_aggregate_at_depth_p (context type depth)
  (declare (type (ptr native_compile_context) context)
           (type usize type depth) (returns c-int))
  (if (< 128 depth) 0
      (if (= (source_type_reference_p context type) 0) 0
          (let ((layouts (source_layouts context)))
            (let ((index (native_find_layout layouts type)))
              (if (= index 0) 0
                  (source_aggregate_layout_p context (native_layout_at layouts (wrap- index 1)) depth)))))))

(defun source_aggregate_type_p (context type)
  (declare (type (ptr native_compile_context) context)
           (type usize type) (returns c-int))
  (source_aggregate_at_depth_p context type 0))
