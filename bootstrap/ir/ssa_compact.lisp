(include "ssa_branch.lisp")
(include "ssa_remap.lisp")

;; Copies move toward lower arena indices; records never partially overlap.
(defun ssa_move_record (destination source remaining)
  (declare (type (ptr u8) destination source) (type usize remaining) (returns c-int))
  (if (= remaining 0) 1
      (progn
        (store destination (deref source))
        (ssa_move_record (pointer+ destination 1) (pointer+ source 1) (wrap- remaining 1)))))

(defun ssa_compact_values (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'value_count)) index) 1
      (let ((value (ssa_value_at arena index)))
        (let ((mapped (deref (field-pointer value 'remap))))
          (if (= mapped 0) (wrap-cast c-int 1)
              (let ((destination (ssa_value_at arena mapped)))
                (if (= mapped index) (wrap-cast c-int 1)
                    (ssa_move_record (ptr-cast (ptr u8) destination) (ptr-cast (ptr u8) value)
                                     (sizeof 'native_ssa_value)))
                (ssa_record_type arena mapped destination)))
          (ssa_compact_values arena (wrap+ index 1))))))

(defun ssa_compact_blocks (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 1
      (let ((block (ssa_block_at arena index)))
        (let ((mapped (deref (field-pointer block 'remap))))
          (if (= mapped 0) (wrap-cast c-int 1)
              (if (= mapped index) (wrap-cast c-int 1)
                  (ssa_move_record (ptr-cast (ptr u8) (ssa_block_at arena mapped))
                                   (ptr-cast (ptr u8) block) (sizeof 'native_ssa_block))))
          (ssa_compact_blocks arena (wrap+ index 1))))))

(defun ssa_compact_cfg (arena blocks values)
  (declare (type (ptr native_ssa_arena) arena) (type usize blocks values) (returns c-int))
  (ssa_remap_values arena 1)
  (ssa_remap_blocks arena 1)
  (store (field-pointer arena 'current) (ssa_mapped_block arena (deref (field-pointer arena 'current))))
  (ssa_compact_values arena 1)
  (ssa_compact_blocks arena 1)
  (store (field-pointer arena 'value_count) values)
  (store (field-pointer arena 'block_count) blocks)
  1)

(defun ssa_prune_cfg (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (ssa_clear_visits arena 1)
    (ssa_mark_reachable arena 1)
    (if (= (ssa_repair_phis arena 1) 0) 0
        (let ((blocks (ssa_map_blocks arena 1 0)))
          (let ((values (ssa_map_values arena 1 0)))
            (ssa_compact_cfg arena blocks values)
            (ssa_verify_function context))))))
