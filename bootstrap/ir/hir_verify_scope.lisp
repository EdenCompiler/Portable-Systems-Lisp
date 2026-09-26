;; Structural checks for scalar lexical bindings. The ordinary HIR pass
;; verifies node shape and types; the scope pass follows lexical let nesting.

(defun hir_previous_binding_p (arena previous reference)
  (declare (type (ptr native_hir_arena) arena)
           (type usize previous reference)
           (returns c-int))
  (if (= previous 0)
      1
      (if (= (hir_child_before_p previous reference) 0)
          0
          (if (= (deref (field-pointer
                  (hir_node_at arena previous) 'kind)) 14) 1 0))))

(defun hir_local_binding_shape_p (arena node reference)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type usize reference)
           (returns c-int))
  (let ((initializer (deref (field-pointer node 'left)))
        (previous (deref (field-pointer node 'target)))
        (slot (deref (field-pointer node 'value))))
    (if (= (hir_child_before_p initializer reference) 0)
        0
        (if (= (hir_child_type_p arena initializer
                                 (deref (field-pointer node 'type_code))) 0)
            0
            (if (= (deref (field-pointer node 'right)) 0)
                (if (< 0 slot)
                    (if (< (deref (field-pointer arena 'count))
                           (wrap-cast usize slot))
                        0
                        (hir_previous_binding_p arena previous reference))
                    0)
                0)))))

(defun hir_verify_local_binding (arena node reference functions prior_count
                                  arity depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth)
           (returns c-int))
  (if (= (hir_local_binding_shape_p arena node reference) 0)
      0
      (hir_verify_node arena (deref (field-pointer node 'left)) functions
                       prior_count arity (wrap+ depth 1))))

(defun hir_verify_local_read (arena node reference)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type usize reference)
           (returns c-int))
  (let ((binding (deref (field-pointer node 'target))))
    (if (= (deref (field-pointer node 'value)) 0)
        (if (= (deref (field-pointer node 'left)) 0)
            (if (= (deref (field-pointer node 'right)) 0)
                (if (= (hir_child_before_p binding reference) 1)
                    (if (= (deref (field-pointer
                            (hir_node_at arena binding) 'kind)) 14)
                        (hir_child_type_p arena binding
                                          (deref (field-pointer node 'type_code)))
                        0)
                    0)
                0)
            0)
        0)))

(defun hir_let_shape_p (arena node reference)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type usize reference)
           (returns c-int))
  (let ((binding (deref (field-pointer node 'left)))
        (body (deref (field-pointer node 'right))))
    (if (= (deref (field-pointer node 'value)) 0)
        (if (= (deref (field-pointer node 'target)) 0)
            (if (= (hir_child_before_p binding reference) 1)
                (if (= (hir_child_before_p body reference) 1)
                    (if (= (deref (field-pointer
                            (hir_node_at arena binding) 'kind)) 14)
                        (hir_child_type_p arena body
                                          (deref (field-pointer node 'type_code)))
                        0)
                    0)
                0)
            0)
        0)))

(defun hir_verify_let (arena node reference functions prior_count arity depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth)
           (returns c-int))
  (if (= (hir_let_shape_p arena node reference) 0)
      0
      (if (= (hir_verify_node arena (deref (field-pointer node 'left))
                              functions prior_count arity
                              (wrap+ depth 1)) 0)
          0
          (hir_verify_node arena (deref (field-pointer node 'right))
                           functions prior_count arity (wrap+ depth 1)))))

(defun hir_binding_in_scope (arena binding scope depth)
  (declare (type (ptr native_hir_arena) arena)
           (type usize binding scope depth)
           (returns c-int))
  (if (< 128 depth)
      0
      (if (= scope 0)
          0
          (if (= binding scope)
              1
              (hir_binding_in_scope
               arena binding
               (deref (field-pointer (hir_node_at arena scope) 'target))
               (wrap+ depth 1))))))

(defun hir_verify_scope_pair (arena node scope depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type usize scope depth)
           (returns c-int))
  (let ((left (deref (field-pointer node 'left)))
        (right (deref (field-pointer node 'right))))
    (if (= left 0)
        (if (= right 0) 1 (hir_verify_scope arena right scope
                                            (wrap+ depth 1)))
        (if (= (hir_verify_scope arena left scope (wrap+ depth 1)) 0)
            0
            (if (= right 0)
                1
                (hir_verify_scope arena right scope (wrap+ depth 1)))))))

(defun hir_verify_scope_let (arena node scope depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type usize scope depth)
           (returns c-int))
  (let ((binding (deref (field-pointer node 'left))))
    (let ((entry (hir_node_at arena binding)))
      (if (= (deref (field-pointer entry 'target)) scope)
          (if (= (hir_verify_scope
                  arena (deref (field-pointer entry 'left)) scope
                  (wrap+ depth 1)) 1)
              (hir_verify_scope arena (deref (field-pointer node 'right))
                                binding (wrap+ depth 1))
              0)
          0))))

(defun hir_verify_scope (arena reference scope depth)
  (declare (type (ptr native_hir_arena) arena)
           (type usize reference scope depth)
           (returns c-int))
  (if (< 128 depth)
      0
      (let ((node (hir_node_at arena reference)))
        (let ((kind (deref (field-pointer node 'kind))))
          (cond
            ((= kind 1) 1)
            ((= kind 2) 1)
            ((= kind 14) 0)
            ((= kind 15)
             (hir_binding_in_scope
              arena (deref (field-pointer node 'target)) scope depth))
            ((= kind 16) (hir_verify_scope_let arena node scope depth))
            ((= kind 10)
             (if (= (hir_verify_scope_pair arena node scope depth) 1)
                 (hir_verify_scope arena
                                   (deref (field-pointer node 'target))
                                   scope (wrap+ depth 1))
                 0))
            (t (hir_verify_scope_pair arena node scope depth)))))))
