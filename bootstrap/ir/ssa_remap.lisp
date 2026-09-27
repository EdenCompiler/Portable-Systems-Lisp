;; Build dense IDs, then rewrite every surviving edge before moving records.

(defun ssa_map_blocks (arena index count)
  (declare (type (ptr native_ssa_arena) arena) (type usize index count) (returns usize))
  (if (< (deref (field-pointer arena 'block_count)) index) count
      (let ((block (ssa_block_at arena index)))
        (if (= (deref (field-pointer block 'visit)) 1)
            (progn
              (store (field-pointer block 'remap) (wrap+ count 1))
              (ssa_map_blocks arena (wrap+ index 1) (wrap+ count 1)))
            (progn
              (store (field-pointer block 'remap) 0)
              (ssa_map_blocks arena (wrap+ index 1) count))))))

(defun ssa_map_values (arena index count)
  (declare (type (ptr native_ssa_arena) arena) (type usize index count) (returns usize))
  (if (< (deref (field-pointer arena 'value_count)) index) count
      (let ((value (ssa_value_at arena index)))
        (let ((block (ssa_block_at arena (deref (field-pointer value 'block)))))
          (if (= (deref (field-pointer block 'remap)) 0)
              (progn
                (store (field-pointer value 'remap) 0)
                (ssa_map_values arena (wrap+ index 1) count))
              (progn
                (store (field-pointer value 'remap) (wrap+ count 1))
                (ssa_map_values arena (wrap+ index 1) (wrap+ count 1))))))))

(defun ssa_mapped_value (arena reference)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference) (returns usize))
  (if (= reference 0) 0 (deref (field-pointer (ssa_value_at arena reference) 'remap))))

(defun ssa_mapped_block (arena reference)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference) (returns usize))
  (if (= reference 0) 0 (deref (field-pointer (ssa_block_at arena reference) 'remap))))

(defun ssa_remap_value (arena value)
  (declare (type (ptr native_ssa_arena) arena) (type (ptr native_ssa_value) value)
           (returns c-int))
  (store (field-pointer value 'left) (ssa_mapped_value arena (deref (field-pointer value 'left))))
  (store (field-pointer value 'right) (ssa_mapped_value arena (deref (field-pointer value 'right))))
  (store (field-pointer value 'next) (ssa_mapped_value arena (deref (field-pointer value 'next))))
  (store (field-pointer value 'block) (ssa_mapped_block arena (deref (field-pointer value 'block))))
  (store (field-pointer value 'predecessor_left)
         (ssa_mapped_block arena (deref (field-pointer value 'predecessor_left))))
  (store (field-pointer value 'predecessor_right)
         (ssa_mapped_block arena (deref (field-pointer value 'predecessor_right))))
  1)

(defun ssa_remap_values (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'value_count)) index) 1
      (let ((value (ssa_value_at arena index)))
        (if (= (deref (field-pointer value 'remap)) 0) (wrap-cast c-int 1)
            (ssa_remap_value arena value))
        (ssa_remap_values arena (wrap+ index 1)))))

(defun ssa_remap_block (arena block)
  (declare (type (ptr native_ssa_arena) arena) (type (ptr native_ssa_block) block)
           (returns c-int))
  (store (field-pointer block 'first) (ssa_mapped_value arena (deref (field-pointer block 'first))))
  (store (field-pointer block 'last) (ssa_mapped_value arena (deref (field-pointer block 'last))))
  (store (field-pointer block 'condition) (ssa_mapped_value arena (deref (field-pointer block 'condition))))
  (store (field-pointer block 'result) (ssa_mapped_value arena (deref (field-pointer block 'result))))
  (store (field-pointer block 'target_left) (ssa_mapped_block arena (deref (field-pointer block 'target_left))))
  (store (field-pointer block 'target_right) (ssa_mapped_block arena (deref (field-pointer block 'target_right))))
  1)

(defun ssa_remap_blocks (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 1
      (let ((block (ssa_block_at arena index)))
        (if (= (deref (field-pointer block 'remap)) 0) (wrap-cast c-int 1)
            (ssa_remap_block arena block))
        (ssa_remap_blocks arena (wrap+ index 1)))))
