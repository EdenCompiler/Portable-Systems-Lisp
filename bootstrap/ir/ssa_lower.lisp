;; HIR -> SSA preserves source-order effects. Lexical bindings become aliases
;; of immutable SSA values; no machine stack slots or registers appear here.

(defun ssa_binding_slot (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns (ptr usize)))
  (pointer+ (deref (field-pointer context 'bindings))
            (wrap-cast isize (wrap- reference 1))))

(defun ssa_lower_pair (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns usize))
  (let ((left (ssa_lower_expr context (deref (field-pointer node 'left)) (wrap+ depth 1))))
    (if (= left 0) 0
        (let ((right (if (= (deref (field-pointer node 'right)) 0)
                         (wrap-cast usize 0)
                         (ssa_lower_expr context (deref (field-pointer node 'right))
                                         (wrap+ depth 1)))))
          (if (= (deref (field-pointer node 'right)) 0)
              (ssa_new_value (deref (field-pointer context 'ssa)) node left 0)
              (if (= right 0) 0
                  (ssa_new_value (deref (field-pointer context 'ssa)) node left right)))))))

(defun ssa_lower_arguments (context chain depth)
  (declare (type (ptr native_compile_context) context)
           (type usize chain depth) (returns usize))
  (if (< 128 depth) 0
      (if (= chain 0) 0
          (let ((node (hir_node_at (deref (field-pointer context 'hir)) chain)))
            (let ((previous (ssa_lower_arguments context (deref (field-pointer node 'right))
                                                 (wrap+ depth 1))))
              (if (= previous 0)
                  (if (= (deref (field-pointer node 'right)) 0)
                      (ssa_lower_argument_value context node previous depth) 0)
                  (ssa_lower_argument_value context node previous depth)))))))

(defun ssa_lower_argument_value (context node previous depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize previous depth) (returns usize))
  (let ((value (ssa_lower_expr context (deref (field-pointer node 'left)) (wrap+ depth 1))))
    (if (= value 0) 0
        (ssa_new_value (deref (field-pointer context 'ssa)) node value previous))))

(defun ssa_lower_call (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns usize))
  (let ((chain (ssa_lower_arguments context (deref (field-pointer node 'left)) depth)))
    (if (= chain 0)
        (if (= (deref (field-pointer node 'left)) 0)
            (ssa_new_value (deref (field-pointer context 'ssa)) node 0 0) 0)
        (ssa_new_value (deref (field-pointer context 'ssa)) node chain 0))))

(defun ssa_lower_binding (context node reference depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize reference depth) (returns usize))
  (let ((value (ssa_lower_expr context (deref (field-pointer node 'left)) (wrap+ depth 1))))
    (if (= value 0) 0
        (progn (store (ssa_binding_slot context reference) value) value))))

(defun ssa_lower_sequence (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns usize))
  (if (= (ssa_lower_expr context (deref (field-pointer node 'left)) (wrap+ depth 1)) 0) 0
      (ssa_lower_expr context (deref (field-pointer node 'right)) (wrap+ depth 1))))

(defun ssa_lower_expr (context reference depth)
  (declare (type (ptr native_compile_context) context)
           (type usize reference depth) (returns usize))
  (if (< 128 depth) 0
      (let ((node (hir_node_at (deref (field-pointer context 'hir)) reference)))
        (let ((kind (deref (field-pointer node 'kind))))
          (cond
            ((= kind 7) (ssa_lower_call context node depth))
            ((= kind 10) (ssa_lower_if context node depth))
            ((= kind 13) (ssa_lower_sequence context node depth))
            ((= kind 14) (ssa_lower_binding context node reference depth))
            ((= kind 15) (deref (ssa_binding_slot context (deref (field-pointer node 'target)))))
            ((= kind 16) (ssa_lower_sequence context node depth))
            ((= kind 26) (ssa_lower_while context node depth))
            ((= (deref (field-pointer node 'left)) 0)
             (ssa_new_value (deref (field-pointer context 'ssa)) node 0 0))
            (t (ssa_lower_pair context node depth)))))))

(defun ssa_lower_function (context root)
  (declare (type (ptr native_compile_context) context)
           (type usize root) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (store (field-pointer arena 'value_count) 0)
    (store (field-pointer arena 'block_count) 0)
    (store (field-pointer arena 'error) 0)
    (let ((entry (ssa_new_block arena)))
      (if (= entry 0) 0
          (progn
            (store (field-pointer arena 'current) entry)
            (let ((result (ssa_lower_expr context root 0)))
              (if (= result 0) 0
                  (ssa_terminate arena 1 0 0 0 result))))))))
