;; Structural checks keep memory metadata separate from HIR references.
;; Source-type verification checks widths, offsets, and pointee relationships.

(defun hir_memory_metadata_shape_p (node kind)
  (declare (type (ptr native_hir_node) node)
           (type u32 kind) (returns c-int))
  (cond
    ((= kind 23) (if (= (deref (field-pointer node 'target)) 0) 0 1))
    ((= kind 24) (if (= (deref (field-pointer node 'target)) 0) 1 0))
    ((= kind 25) (if (= (deref (field-pointer node 'target)) 0) 1 0))
    ((= kind 27) (if (= (deref (field-pointer node 'target)) 0) 1 0))
    (t (hir_leaf_metadata_p node))))

(defun hir_leaf_metadata_p (node)
  (declare (type (ptr native_hir_node) node) (returns c-int))
  (if (= (deref (field-pointer node 'target)) 0)
      (if (= (deref (field-pointer node 'value)) 0) 1 0)
      0))

(defun hir_memory_right_shape_p (arena node reference kind)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type usize reference)
           (type u32 kind) (returns c-int))
  (let ((right (deref (field-pointer node 'right))))
    (if (= kind 25)
        (if (= (hir_child_before_p right reference) 0) 0
            (hir_child_type_p arena right 1))
        (if (= kind 27)
            (if (= (hir_child_before_p right reference) 0) 0
                (hir_child_type_p arena right 1))
            (if (= kind 26)
                (hir_child_before_p right reference)
                (if (= right 0) 1 0))))))

(defun hir_verify_memory_shape (arena node reference functions count arity depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference count arity depth) (returns c-int))
  (let ((kind (deref (field-pointer node 'kind)))
        (left (deref (field-pointer node 'left))))
    (if (< 27 kind)
        0
        (if (= (hir_child_before_p left reference) 0)
            0
            (if (= (hir_child_type_p arena left (if (= kind 26) 2 1)) 0)
                0
                (if (= (hir_memory_metadata_shape_p node kind) 0)
                    0
                    (if (= (hir_memory_right_shape_p arena node reference kind) 0)
                        0
                        (if (= (hir_verify_node arena left functions count arity
                                                (wrap+ depth 1)) 0)
                            0
                            (if (= (deref (field-pointer node 'right)) 0)
                                1
                                (hir_verify_node arena (deref (field-pointer node 'right))
                                                 functions count arity (wrap+ depth 1)))))))))))
