;; Queries over validated natural layouts. A leaf descriptor keeps its scalar
;; code in the low byte and its byte offset in the remaining bits. CPU modules
;; classify these fields; the source/IR retain their nominal aggregate type.
(defun native_aggregate_leaf_code (leaf)
  (declare (type usize leaf) (returns u32))
  (wrap-cast u32 (bits-and leaf 255)))

(defun native_aggregate_leaf_offset (leaf)
  (declare (type usize leaf) (returns usize))
  (wrap-cast usize (shr64 (wrap-cast u64 leaf) 8)))

(defun native_aggregate_leaf_width (leaf)
  (declare (type usize leaf) (returns usize))
  (let ((code (native_aggregate_leaf_code leaf)))
    (if (= code 13) 4 (if (= code 14) 8
        (wrap-cast usize (shr64 (wrap-cast u64 (scalar_type_bits code)) 3))))))

(defun native_aggregate_field_count (context first count depth)
  (declare (type (ptr native_compile_context) context)
           (type usize first count depth) (returns usize))
  (if (= count 0) 0
      (let ((field (native_field_at (source_layouts context) first)))
        (wrap+ (native_aggregate_leaf_count_at_depth context
                 (deref (field-pointer field 'type_ast)) depth)
               (native_aggregate_field_count context (wrap+ first 1) (wrap- count 1) depth)))))

(defun native_aggregate_leaf_count_at_depth (context type depth)
  (declare (type (ptr native_compile_context) context)
           (type usize type depth) (returns usize))
  (if (< 128 depth) 0
      (if (= (scalar_type_code (deref (field-pointer context 'signatures)) type) 16)
          (let ((layout (native_layout_at (source_layouts context)
                          (wrap- (native_find_layout (source_layouts context) type) 1))))
            (native_aggregate_field_count context (deref (field-pointer layout 'first))
              (deref (field-pointer layout 'count)) (wrap+ depth 1)))
          1)))

(defun native_aggregate_leaf_count (context type)
  (declare (type (ptr native_compile_context) context) (type usize type) (returns usize))
  (native_aggregate_leaf_count_at_depth context type 0))

(defun native_aggregate_find_field (context first count index offset depth)
  (declare (type (ptr native_compile_context) context)
           (type usize first count index offset depth) (returns usize))
  (if (= count 0) 0
      (let ((field (native_field_at (source_layouts context) first)))
        (let ((type (deref (field-pointer field 'type_ast))))
          (let ((leaves (native_aggregate_leaf_count_at_depth context type depth)))
            (if (< index leaves)
                (native_aggregate_leaf_at_depth context type index
                  (wrap+ offset (deref (field-pointer field 'offset))) depth)
                (native_aggregate_find_field context (wrap+ first 1) (wrap- count 1)
                  (wrap- index leaves) offset depth)))))))

(defun native_aggregate_leaf_at_depth (context type index offset depth)
  (declare (type (ptr native_compile_context) context)
           (type usize type index offset depth) (returns usize))
  (if (< 128 depth) 0
      (let ((code (scalar_type_code (deref (field-pointer context 'signatures)) type)))
        (if (= code 16)
            (let ((layout (native_layout_at (source_layouts context)
                            (wrap- (native_find_layout (source_layouts context) type) 1))))
              (native_aggregate_find_field context (deref (field-pointer layout 'first))
                (deref (field-pointer layout 'count)) index offset (wrap+ depth 1)))
            (if (= index 0) (wrap+ (wrap* offset 256) (wrap-cast usize code)) 0)))))

(defun native_aggregate_leaf (context type index)
  (declare (type (ptr native_compile_context) context) (type usize type index) (returns usize))
  (native_aggregate_leaf_at_depth context type index 0 0))

(defun native_aggregate_float_leaf_count (context type index)
  (declare (type (ptr native_compile_context) context) (type usize type index) (returns usize))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) 0
        (wrap+ (if (if (= (native_aggregate_leaf_code leaf) 13) t
                      (= (native_aggregate_leaf_code leaf) 14))
                   (wrap-cast usize 1) (wrap-cast usize 0))
               (native_aggregate_float_leaf_count context type (wrap+ index 1))))))

(defun native_aggregate_hfa_same_p (context type index code)
  (declare (type (ptr native_compile_context) context)
           (type usize type index) (type u32 code) (returns c-int))
  (let ((leaf (native_aggregate_leaf context type index)))
    (if (= leaf 0) 1
        (if (= (native_aggregate_leaf_code leaf) code)
            (native_aggregate_hfa_same_p context type (wrap+ index 1) code) 0))))

(defun native_aggregate_hfa_code (context type)
  (declare (type (ptr native_compile_context) context) (type usize type) (returns u32))
  (let ((count (native_aggregate_leaf_count context type))
        (code (native_aggregate_leaf_code (native_aggregate_leaf context type 0))))
    (if (if (= count 0) t (< 4 count)) 0
        (if (= (native_abi_float_p code) 0) 0
            (if (= (native_aggregate_hfa_same_p context type 1 code) 1) code 0)))))
