;; Fold Boolean branches, then repair PHIs against the reachable CFG.

(defun ssa_fold_branch (arena block)
  (declare (type (ptr native_ssa_arena) arena) (type (ptr native_ssa_block) block)
           (returns c-int))
  (if (= (deref (field-pointer block 'terminator)) 3)
      (let ((test (ssa_value_at arena (deref (field-pointer block 'condition)))))
        (if (= (deref (field-pointer test 'kind)) 19)
            (progn
              (store (field-pointer block 'target_left)
                     (if (= (deref (field-pointer test 'value)) 0)
                         (deref (field-pointer block 'target_right))
                         (deref (field-pointer block 'target_left))))
              (store (field-pointer block 'terminator) 2)
              (store (field-pointer block 'condition) 0)
              (store (field-pointer block 'target_right) 0)
              1) 0)) 0))

(defun ssa_fold_branches (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 0
      (let ((changed (ssa_fold_branch arena (ssa_block_at arena index))))
        (let ((remaining (ssa_fold_branches arena (wrap+ index 1))))
          (if (= changed 1) 1 remaining)))))

(defun ssa_mark_reachable (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (= index 0) 1
      (let ((block (ssa_block_at arena index)))
        (if (= (deref (field-pointer block 'visit)) 1) 1
            (progn
              (store (field-pointer block 'visit) 1)
              (ssa_mark_reachable arena (deref (field-pointer block 'target_left)))
              (ssa_mark_reachable arena (deref (field-pointer block 'target_right))))))))

(defun ssa_surviving_edge_p (arena predecessor successor)
  (declare (type (ptr native_ssa_arena) arena) (type usize predecessor successor)
           (returns c-int))
  (if (= (deref (field-pointer (ssa_block_at arena predecessor) 'visit)) 1)
      (ssa_edge_p arena predecessor successor) 0))

(defun ssa_phi_to_copy (value incoming)
  (declare (type (ptr native_ssa_value) value) (type usize incoming) (returns c-int))
  (store (field-pointer value 'kind) 31)
  (store (field-pointer value 'left) incoming)
  (store (field-pointer value 'right) 0)
  (store (field-pointer value 'predecessor_left) 0)
  (store (field-pointer value 'predecessor_right) 0)
  1)

(defun ssa_repair_phi (arena value)
  (declare (type (ptr native_ssa_arena) arena) (type (ptr native_ssa_value) value)
           (returns c-int))
  (let ((left (ssa_surviving_edge_p arena (deref (field-pointer value 'predecessor_left))
                                    (deref (field-pointer value 'block))))
        (right (ssa_surviving_edge_p arena (deref (field-pointer value 'predecessor_right))
                                     (deref (field-pointer value 'block)))))
    (if (= left 1)
        (if (= right 1) 1 (ssa_phi_to_copy value (deref (field-pointer value 'left))))
        (if (= right 1) (ssa_phi_to_copy value (deref (field-pointer value 'right))) 0))))

(defun ssa_repair_phis (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'value_count)) index) 1
      (let ((value (ssa_value_at arena index)))
        (let ((block (ssa_block_at arena (deref (field-pointer value 'block)))))
          (if (= (deref (field-pointer block 'visit)) 1)
              (if (= (deref (field-pointer value 'kind)) 28)
                  (if (= (ssa_repair_phi arena value) 0) 0
                      (ssa_repair_phis arena (wrap+ index 1)))
                  (ssa_repair_phis arena (wrap+ index 1)))
              (ssa_repair_phis arena (wrap+ index 1)))))))
