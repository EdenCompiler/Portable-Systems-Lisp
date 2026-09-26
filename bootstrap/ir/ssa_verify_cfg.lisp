;; Native CFG and dominance checks. Visits are scratch fields, cleared before
;; each reachability query. Searching without a definition block establishes
;; whether that block dominates a use, including uses on loop backedges.

(defun ssa_clear_visits (arena index)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 1
      (progn
        (store (field-pointer (ssa_block_at arena index) 'visit) 0)
        (ssa_clear_visits arena (wrap+ index 1)))))

(defun ssa_reaches_without (arena block target excluded)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize block target excluded) (returns c-int))
  (if (= block 0) 0
      (if (= block excluded) 0
          (if (= block target) 1
              (let ((node (ssa_block_at arena block)))
                (if (= (deref (field-pointer node 'visit)) 1) 0
                    (progn
                      (store (field-pointer node 'visit) 1)
                      (if (= (ssa_reaches_without arena (deref (field-pointer node 'target_left))
                                                  target excluded) 1) 1
                          (ssa_reaches_without arena (deref (field-pointer node 'target_right))
                                               target excluded)))))))))

(defun ssa_dominates_p (arena definition use)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize definition use) (returns c-int))
  (if (= definition use) 1
      (progn
        (ssa_clear_visits arena 1)
        (if (= (ssa_reaches_without arena 1 use definition) 1) 0 1))))

(defun ssa_edge_p (arena predecessor successor)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize predecessor successor) (returns c-int))
  (let ((block (ssa_block_at arena predecessor)))
    (if (= (deref (field-pointer block 'target_left)) successor) 1
        (if (= (deref (field-pointer block 'target_right)) successor) 1 0))))

(defun ssa_incoming_count (arena successor index)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize successor index) (returns usize))
  (if (< (deref (field-pointer arena 'block_count)) index) 0
      (wrap+ (if (= (ssa_edge_p arena index successor) 1) (wrap-cast usize 1) 0)
             (ssa_incoming_count arena successor (wrap+ index 1)))))

(defun ssa_verify_block_list (arena block reference previous)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize block reference previous) (returns c-int))
  (if (= reference 0)
      (if (= previous (deref (field-pointer (ssa_block_at arena block) 'last))) 1 0)
      (if (= (ir_reference_p reference (deref (field-pointer arena 'value_count))) 0) 0
          (if (< previous reference)
              (let ((value (ssa_value_at arena reference)))
                (if (= (deref (field-pointer value 'block)) block)
                    (ssa_verify_block_list arena block (deref (field-pointer value 'next)) reference) 0))
              0))))

(defun ssa_verify_terminator_shape (arena block)
  (declare (type (ptr native_ssa_arena) arena)
           (type (ptr native_ssa_block) block) (returns c-int))
  (let ((kind (deref (field-pointer block 'terminator)))
        (condition (deref (field-pointer block 'condition)))
        (left (deref (field-pointer block 'target_left)))
        (right (deref (field-pointer block 'target_right)))
        (result (deref (field-pointer block 'result)))
        (blocks (deref (field-pointer arena 'block_count)))
        (values (deref (field-pointer arena 'value_count))))
    (cond
      ((= kind 1)
       (if (= condition 0) (if (= left 0) (if (= right 0) (ir_reference_p result values) 0) 0) 0))
      ((= kind 2)
       (if (= condition 0) (if (= result 0) (if (= right 0) (ir_reference_p left blocks) 0) 0) 0))
      ((= kind 3)
       (if (= result 0)
           (if (= (ir_reference_p condition values) 0) 0
               (if (= (ir_reference_p left blocks) 0) 0 (ir_reference_p right blocks))) 0))
      (t 0))))

(defun ssa_verify_blocks (arena index)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 1
      (let ((block (ssa_block_at arena index)))
        (if (= (ssa_verify_terminator_shape arena block) 0) 0
            (if (= (ssa_verify_block_list arena index (deref (field-pointer block 'first)) 0) 0) 0
                (ssa_verify_blocks arena (wrap+ index 1)))))))

(defun ssa_block_contains_p (arena block reference current)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize block reference current) (returns c-int))
  (if (= current 0) 0
      (if (= current reference) 1
          (ssa_block_contains_p arena block reference (deref (field-pointer (ssa_value_at arena current) 'next))))))

(defun ssa_verify_use (arena reference parent block)
  (declare (type (ptr native_ssa_arena) arena)
           (type usize reference parent block) (returns c-int))
  (if (= reference 0) 1
      (if (< reference parent)
          (ssa_dominates_p arena (deref (field-pointer (ssa_value_at arena reference) 'block)) block) 0)))
