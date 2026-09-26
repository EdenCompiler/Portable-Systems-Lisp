;; Explicit CFG control flow and two-predecessor conditional joins.

(defun ssa_lower_arm (context reference destination join depth)
  (declare (type (ptr native_compile_context) context)
           (type usize reference destination join depth) (returns usize))
  (let ((arena (deref (field-pointer context 'ssa))))
    (store (field-pointer arena 'current) destination)
    (let ((value (ssa_lower_expr context reference (wrap+ depth 1))))
      (if (= value 0) 0
          (if (= (ssa_terminate arena 2 0 join 0 0) 0) 0 value)))))

(defun ssa_make_phi (context node left right predecessor_left predecessor_right)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize left right predecessor_left predecessor_right) (returns usize))
  (let ((arena (deref (field-pointer context 'ssa))))
    (let ((reference (ssa_new_value arena node left right)))
      (if (= reference 0) 0
          (let ((value (ssa_value_at arena reference)))
            (store (field-pointer value 'kind) 28)
            (store (field-pointer value 'target) 0)
            (store (field-pointer value 'predecessor_left) predecessor_left)
            (store (field-pointer value 'predecessor_right) predecessor_right)
            (ssa_record_type arena reference value)
            reference)))))

(defun ssa_lower_if_arms (context node then_block else_block join depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize then_block else_block join depth) (returns usize))
  (let ((arena (deref (field-pointer context 'ssa))))
    (let ((left (ssa_lower_arm context (deref (field-pointer node 'right))
                               then_block join depth)))
      (if (= left 0) 0
          (let ((then_end (deref (field-pointer arena 'current))))
            (let ((right (ssa_lower_arm context (deref (field-pointer node 'target))
                                        else_block join depth)))
              (if (= right 0) 0
                  (let ((else_end (deref (field-pointer arena 'current))))
                    (store (field-pointer arena 'current) join)
                    (ssa_make_phi context node left right then_end else_end)))))))))

(defun ssa_lower_if (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns usize))
  (let ((arena (deref (field-pointer context 'ssa))))
    (let ((test (ssa_lower_expr context (deref (field-pointer node 'left)) (wrap+ depth 1))))
      (if (= test 0) 0
          (let ((then_block (ssa_new_block arena))
                (else_block (ssa_new_block arena))
                (join (ssa_new_block arena)))
            (if (= join 0) 0
                (if (= (ssa_terminate arena 3 test then_block else_block 0) 0) 0
                    (ssa_lower_if_arms context node then_block else_block join depth))))))))

(defun ssa_lower_while_blocks (context node header body exit depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize header body exit depth) (returns usize))
  (let ((arena (deref (field-pointer context 'ssa))))
    (store (field-pointer arena 'current) header)
    (let ((test (ssa_lower_expr context (deref (field-pointer node 'left)) (wrap+ depth 1))))
      (if (= test 0) 0
          (if (= (ssa_terminate arena 3 test body exit 0) 0) 0
              (progn
                (store (field-pointer arena 'current) body)
                (if (= (ssa_lower_expr context (deref (field-pointer node 'right))
                                      (wrap+ depth 1)) 0) 0
                    (if (= (ssa_terminate arena 2 0 header 0 0) 0) 0
                        (ssa_make_loop_result context node exit)))))))))

(defun ssa_make_loop_result (context node exit)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize exit) (returns usize))
  (let ((arena (deref (field-pointer context 'ssa))))
    (store (field-pointer arena 'current) exit)
    (let ((reference (ssa_new_value arena node 0 0)))
      (if (= reference 0) 0
          (let ((value (ssa_value_at arena reference)))
            (store (field-pointer value 'kind) 19)
            (ssa_record_type arena reference value)
            reference)))))

(defun ssa_lower_while (context node depth)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_hir_node) node)
           (type usize depth) (returns usize))
  (let ((arena (deref (field-pointer context 'ssa))))
    (let ((header (ssa_new_block arena))
          (body (ssa_new_block arena))
          (exit (ssa_new_block arena)))
      (if (= exit 0) 0
          (if (= (ssa_terminate arena 2 0 header 0 0) 0) 0
              (ssa_lower_while_blocks context node header body exit depth))))))
