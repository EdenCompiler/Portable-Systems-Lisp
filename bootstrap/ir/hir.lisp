(include "../backend/common.lisp")

;; Integer nodes use a 64-bit word representation. Scalar codes retain their
;; source width and signedness; source code 11 is a raw pointer. References are one-based
;; arena indices and point
;; only to earlier nodes. Kinds: 1 literal, 2 parameter, 4/5/6 arithmetic,
;; 7 direct call, 8/9 comparison, 10 conditional, 11 bitwise and, 12 shift,
;; 13 sequence, 14 local binding, 15 local read, 16 lexical let,
;; 17 call-argument link, 18 integer cast, 19 Boolean literal, 20 word truth,
;; 21 address to pointer, 22 pointer cast, 23 field pointer, 24 load,
;; 25 store, 26 while, 27 pointer arithmetic. Pointee is a type AST reference.
;; Call links chain backward through
;; right references.
;; Source is a parser-node
;; reference for later diagnostics. Comparisons have Boolean type code 2.
(defcstruct native_hir_node
  (kind u32)
  (type_code u32)
  (value u64)
  (left usize)
  (right usize)
  (target usize)
  (source usize)
  (scalar_code u32)
  (pointee usize))

(defcstruct native_hir_arena
  (nodes (ptr native_hir_node))
  (count usize)
  (capacity usize)
  (error u32))

(defun hir_node_at (arena reference)
  (declare (type (ptr native_hir_arena) arena)
           (type usize reference)
           (returns (ptr native_hir_node)))
  (pointer+ (deref (field-pointer arena 'nodes))
            (wrap-cast isize (wrap- reference 1))))

(defun hir_new (arena kind value left right target source)
  (declare (type (ptr native_hir_arena) arena)
           (type u32 kind)
           (type u64 value)
           (type usize left right target source)
           (returns usize))
  (let ((count (deref (field-pointer arena 'count))))
    (if (< count (deref (field-pointer arena 'capacity)))
        (let ((reference (wrap+ count 1)))
          (let ((node (hir_node_at arena reference)))
            (store (field-pointer node 'kind) kind)
            (store (field-pointer node 'type_code)
                   (if (= kind 8)
                       2
                       (if (= kind 9) 2 1)))
            (store (field-pointer node 'value) value)
            (store (field-pointer node 'left) left)
            (store (field-pointer node 'right) right)
            (store (field-pointer node 'target) target)
            (store (field-pointer node 'source) source)
            (store (field-pointer node 'scalar_code)
                   (if (= kind 8) 0 (if (= kind 9) 0 1)))
            (store (field-pointer node 'pointee) 0)
            (store (field-pointer arena 'count) reference)
            reference))
        (progn
          (store (field-pointer arena 'error) 1)
          0))))

(defun hir_new_scalar (arena kind value left right target source code)
  (declare (type (ptr native_hir_arena) arena)
           (type u32 kind code)
           (type u64 value)
           (type usize left right target source)
           (returns usize))
  (let ((reference (hir_new arena kind value left right target source)))
    (if (= reference 0)
        0
        (progn
          (store (field-pointer (hir_node_at arena reference) 'scalar_code)
                 code)
          (store (field-pointer (hir_node_at arena reference) 'type_code)
                 (if (= code 0) 2 1))
          reference))))

(defun hir_scalar_code (arena reference)
  (declare (type (ptr native_hir_arena) arena)
           (type usize reference)
           (returns u32))
  (deref (field-pointer (hir_node_at arena reference) 'scalar_code)))

(defun hir_pointee (arena reference)
  (declare (type (ptr native_hir_arena) arena)
           (type usize reference) (returns usize))
  (deref (field-pointer (hir_node_at arena reference) 'pointee)))

(defun hir_with_pointee (arena reference pointee)
  (declare (type (ptr native_hir_arena) arena)
           (type usize reference pointee) (returns usize))
  (if (= reference 0)
      0
      (progn
        (store (field-pointer (hir_node_at arena reference) 'pointee) pointee)
        reference)))

(defun hir_copy_type (arena reference source)
  (declare (type (ptr native_hir_arena) arena)
           (type usize reference source) (returns usize))
  (hir_with_pointee arena reference (hir_pointee arena source)))

(defun hir_child_before_p (child parent)
  (declare (type usize child parent) (returns c-int))
  (if (= child 0)
      0
      (if (< child parent) 1 0)))

(defun hir_child_type_p (arena child expected)
  (declare (type (ptr native_hir_arena) arena)
           (type usize child)
           (type u32 expected)
           (returns c-int))
  (if (= (deref (field-pointer (hir_node_at arena child)
                             'type_code)) expected)
      1
      0))

(defun hir_leaf_shape_p (node)
  (declare (type (ptr native_hir_node) node) (returns c-int))
  (if (= (deref (field-pointer node 'left)) 0)
      (if (= (deref (field-pointer node 'right)) 0)
          (if (= (deref (field-pointer node 'target)) 0) 1 0)
          0)
      0))

(defun hir_parameter_shape_p (node arity)
  (declare (type (ptr native_hir_node) node)
           (type usize arity)
           (returns c-int))
  (let ((index (deref (field-pointer node 'value))))
    (if (= index 0)
        0
        (if (< arity (wrap-cast usize index))
            0
            (hir_leaf_shape_p node)))))

(defun hir_verify_binary (arena node reference functions prior_count arity
                          depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth)
           (returns c-int))
  (let ((left (deref (field-pointer node 'left)))
        (right (deref (field-pointer node 'right))))
    (if (< 0 (deref (field-pointer node 'target)))
        0
        (if (< 0 (deref (field-pointer node 'value)))
            0
            (if (= (hir_child_before_p left reference) 0)
                0
                (if (= (hir_child_before_p right reference) 0)
                    0
                    (if (= (hir_child_type_p arena left 1) 0)
                        0
                        (if (= (hir_child_type_p arena right 1) 0)
                            0
                            (if (= (hir_verify_node
                                    arena left functions prior_count arity
                                    (wrap+ depth 1)) 0)
                                0
                                (hir_verify_node
                                 arena right functions prior_count arity
                                 (wrap+ depth 1)))))))))))

(defun hir_verify_if (arena node reference functions prior_count arity depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth)
           (returns c-int))
  (let ((condition (deref (field-pointer node 'left)))
        (then_value (deref (field-pointer node 'right)))
        (else_value (deref (field-pointer node 'target))))
    (if (< 0 (deref (field-pointer node 'value)))
        0
        (if (= (hir_child_before_p condition reference) 0)
            0
            (if (= (hir_child_before_p then_value reference) 0)
                0
                (if (= (hir_child_before_p else_value reference) 0)
                    0
                    (if (= (hir_child_type_p arena condition 2) 0)
                        0
                            (if (= (hir_child_type_p arena then_value
                                     (deref (field-pointer node 'type_code))) 0)
                            0
                            (if (= (hir_child_type_p arena else_value
                                     (deref (field-pointer node 'type_code))) 0)
                                0
                                (if (= (hir_verify_node
                                        arena condition functions prior_count
                                        arity (wrap+ depth 1)) 0)
                                    0
                                    (if (= (hir_verify_node
                                            arena then_value functions
                                            prior_count arity
                                            (wrap+ depth 1)) 0)
                                        0
                                        (hir_verify_node
                                         arena else_value functions
                                         prior_count arity
                                         (wrap+ depth 1)))))))))))))

(defun hir_boolean_result_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (cond
    ((= kind 8) 1)
    ((= kind 9) 1)
    ((= kind 19) 1)
    ((= kind 20) 1)
    ((= kind 26) 1)
    (t 0)))

(defun hir_flexible_result_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (if (= kind 10) 1 (if (< 12 kind) (if (< kind 17) 1 0) 0)))

(defun hir_type_matches_kind_p (node kind)
  (declare (type (ptr native_hir_node) node)
           (type u32 kind) (returns c-int))
  (let ((code (deref (field-pointer node 'type_code))))
    (if (= (hir_boolean_result_kind_p kind) 1)
        (if (= code 2) 1 0)
        (if (= (hir_flexible_result_kind_p kind) 1)
            (if (= code 1) 1 (if (= code 2) 1 0))
            (if (= code 1) 1 0)))))

(defun hir_sequence_shape_p (arena node reference)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type usize reference) (returns c-int))
  (if (= (deref (field-pointer node 'value)) 0)
      (if (= (deref (field-pointer node 'target)) 0)
          (if (= (hir_child_before_p (deref (field-pointer node 'left)) reference) 1)
              (if (= (hir_child_before_p (deref (field-pointer node 'right)) reference) 1)
                  (hir_child_type_p arena (deref (field-pointer node 'right))
                                    (deref (field-pointer node 'type_code)))
                  0)
              0)
          0)
      0))

(defun hir_verify_sequence (arena node reference functions prior_count arity depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth) (returns c-int))
  (if (= (hir_sequence_shape_p arena node reference) 0)
      0
      (if (= (hir_verify_node arena (deref (field-pointer node 'left))
                              functions prior_count arity (wrap+ depth 1)) 0)
          0
          (hir_verify_node arena (deref (field-pointer node 'right))
                           functions prior_count arity (wrap+ depth 1)))))

(defun hir_call_link_shape_p (arena link chain parent)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) link)
           (type usize chain parent)
           (returns c-int))
  (let ((argument (deref (field-pointer link 'left))))
    (if (= (hir_child_before_p chain parent) 0)
        0
        (if (= (deref (field-pointer link 'kind)) 17)
            (if (= (deref (field-pointer link 'type_code)) 1)
                (if (= (deref (field-pointer link 'value)) 0)
                    (if (= (deref (field-pointer link 'target)) 0)
                        (if (= (deref (field-pointer link 'source)) 0)
                            0
                            (if (= (hir_child_before_p argument chain) 0)
                                0
                                (hir_child_type_p arena argument 1)))
                        0)
                    0)
                0)
            0))))

(defun hir_verify_call_arguments (arena chain parent functions prior_count
                                  arity depth expected)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_function) functions)
           (type usize chain parent prior_count arity depth expected)
           (returns c-int))
  (if (= expected 0)
      (if (= chain 0) 1 0)
      (if (= (hir_child_before_p chain parent) 0)
          0
          (let ((link (hir_node_at arena chain)))
            (if (= (hir_call_link_shape_p arena link chain parent) 0)
                0
                (if (= (hir_verify_node
                        arena (deref (field-pointer link 'left)) functions
                        prior_count arity (wrap+ depth 1)) 0)
                    0
                    (hir_verify_call_arguments
                     arena (deref (field-pointer link 'right)) chain
                     functions prior_count arity (wrap+ depth 1)
                     (wrap- expected 1))))))))

(defun hir_verify_call (arena node reference functions prior_count arity
                        depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth)
           (returns c-int))
  (let ((target (deref (field-pointer node 'target))))
    (if (< 0 (deref (field-pointer node 'value)))
        0
        (if (< 0 (deref (field-pointer node 'right)))
            0
            (if (= target 0)
                0
                (if (< prior_count target)
                    0
                    (let ((function (native_function_at functions
                                                        (wrap- target 1))))
                      (hir_verify_call_arguments
                       arena (deref (field-pointer node 'left)) reference
                       functions prior_count arity depth
                       (deref (field-pointer function 'arity))))))))))

(include "hir_verify_scope.lisp")

(defun hir_verify_integer_unary (arena node reference functions prior_count arity depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_hir_node) node)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth)
           (returns c-int))
  (let ((child (deref (field-pointer node 'left))))
    (if (= (hir_child_before_p child reference) 0)
        0
        (if (= (hir_child_type_p arena child 1) 0)
            0
            (if (= (deref (field-pointer node 'right)) 0)
                (if (= (deref (field-pointer node 'target)) 0)
                    (if (= (deref (field-pointer node 'value)) 0)
                        (hir_verify_node arena child functions prior_count
                                         arity (wrap+ depth 1))
                        0)
                    0)
                0)))))

(include "hir_verify_memory_shape.lisp")

(defun hir_verify_node (arena reference functions prior_count arity depth)
  (declare (type (ptr native_hir_arena) arena)
           (type (ptr native_function) functions)
           (type usize reference prior_count arity depth)
           (returns c-int))
  (if (< 128 depth)
      0
      (if (= reference 0)
          0
          (if (< (deref (field-pointer arena 'count)) reference)
              0
              (let ((node (hir_node_at arena reference)))
                (let ((kind (deref (field-pointer node 'kind))))
                (if (= (hir_type_matches_kind_p node kind) 1)
                    (if (= (deref (field-pointer node 'source)) 0)
                        0
                          (cond
                            ((= kind 1) (hir_leaf_shape_p node))
                            ((= kind 2)
                             (hir_parameter_shape_p node arity))
                            ((= kind 4)
                             (hir_verify_binary arena node reference
                                                functions prior_count arity
                                                depth))
                            ((= kind 5)
                             (hir_verify_binary arena node reference
                                                functions prior_count arity
                                                depth))
                            ((= kind 6)
                             (hir_verify_binary arena node reference
                                                functions prior_count arity
                                                depth))
                            ((= kind 11)
                             (hir_verify_binary arena node reference
                                                functions prior_count arity
                                                depth))
                            ((= kind 12)
                             (hir_verify_binary arena node reference
                                                functions prior_count arity
                                                depth))
                            ((= kind 13)
                             (hir_verify_sequence arena node reference
                                                  functions prior_count arity
                                                  depth))
                            ((= kind 14)
                             (hir_verify_local_binding arena node reference
                                                       functions prior_count
                                                       arity depth))
                            ((= kind 15)
                             (hir_verify_local_read arena node reference))
                            ((= kind 16)
                             (hir_verify_let arena node reference functions
                                             prior_count arity depth))
                            ((= kind 18)
                             (hir_verify_integer_unary arena node reference functions
                                                       prior_count arity depth))
                            ((= kind 19)
                             (if (< 1 (deref (field-pointer node 'value)))
                                 0 (hir_leaf_shape_p node)))
                            ((= kind 20)
                             (hir_verify_integer_unary arena node reference functions
                                                       prior_count arity depth))
                            ((= kind 7)
                             (hir_verify_call arena node reference functions
                                              prior_count arity depth))
                            ((= kind 8)
                             (hir_verify_binary arena node reference
                                                functions prior_count arity
                                                depth))
                            ((= kind 9)
                             (hir_verify_binary arena node reference
                                                functions prior_count arity
                                                depth))
                            ((= kind 10)
                             (hir_verify_if arena node reference functions
                                            prior_count arity depth))
                            ((< 20 kind)
                             (hir_verify_memory_shape arena node reference functions
                                                      prior_count arity depth))
                            (t 0)))
                    0)))))))

(defun hir_verify_root (arena root functions prior_count arity)
  (declare (type (ptr native_hir_arena) arena)
           (type usize root prior_count arity)
           (type (ptr native_function) functions)
           (returns c-int)
           (c-export :c))
  (if (= (deref (field-pointer arena 'error)) 0)
      (if (= (hir_verify_node arena root functions prior_count arity 0) 1)
          (if (= (hir_verify_scope arena root 0 0) 1)
              (hir_child_type_p arena root 1)
              0)
          0)
      0))
