;; Call summaries describe allocation only. Nonallocating calls may still
;; write memory, perform I/O, or diverge; optimizer effect roots are unchanged.

(defun hir_call_allocation_free_p (context target require_ready)
  (declare (type (ptr native_compile_context) context) (type usize target)
           (type c-int require_ready) (returns c-int))
  (let ((signature (native_signature_at (deref (field-pointer context 'signatures))
                                        (wrap- target 1))))
    (if (= (deref (field-pointer signature 'allocation_free)) 1)
        (if (= require_ready 0) 1
            (if (= (deref (field-pointer signature 'effect_ready)) 1) 1 0)) 0)))

(defun hir_function_unsafe_call (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns usize))
  (let ((arena (deref (field-pointer context 'hir))))
    (if (< (deref (field-pointer arena 'count)) index) 0
        (let ((node (hir_node_at arena index)))
          (if (= (deref (field-pointer node 'kind)) 7)
              (if (= (hir_call_allocation_free_p context (deref (field-pointer node 'target)) 0) 0)
                  (deref (field-pointer node 'target))
                  (hir_function_unsafe_call context (wrap+ index 1)))
              (hir_function_unsafe_call context (wrap+ index 1)))))))

(defun hir_region_unsafe_call (context reference depth)
  (declare (type (ptr native_compile_context) context) (type usize reference depth)
           (returns usize))
  (if (= reference 0) 0
      (let ((node (hir_node_at (deref (field-pointer context 'hir)) reference)))
        (let ((kind (deref (field-pointer node 'kind))))
          (if (= kind 7)
              (if (= (hir_call_allocation_free_p context (deref (field-pointer node 'target)) 1) 0)
                  (deref (field-pointer node 'target))
                  (hir_region_children_unsafe_call context node depth))
              (hir_region_children_unsafe_call context node depth))))))

(defun hir_region_children_unsafe_call (context node depth)
  (declare (type (ptr native_compile_context) context) (type (ptr native_hir_node) node)
           (type usize depth) (returns usize))
  (let ((left (hir_region_unsafe_call context (deref (field-pointer node 'left)) (wrap+ depth 1))))
    (if (= left 0)
        (let ((right (hir_region_unsafe_call context (deref (field-pointer node 'right)) (wrap+ depth 1))))
          (if (= right 0)
              (if (= (deref (field-pointer node 'kind)) 10)
                  (hir_region_unsafe_call context (deref (field-pointer node 'target)) (wrap+ depth 1)) 0)
              right)) left)))

(defun hir_regions_unsafe_call (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns usize))
  (let ((arena (deref (field-pointer context 'hir))))
    (if (< (deref (field-pointer arena 'count)) index) 0
        (let ((node (hir_node_at arena index)))
          (if (= (deref (field-pointer node 'allocation_region)) 0)
              (hir_regions_unsafe_call context (wrap+ index 1))
              (let ((unsafe (hir_region_unsafe_call context index 0)))
                (if (= unsafe 0) (hir_regions_unsafe_call context (wrap+ index 1)) unsafe)))))))
