;; Insert definitions before the call's old ID, preserving topological IDs.
;; Move records upward in descending order, then rewrite all value references.
;; Block IDs and CFG edges remain unchanged.

(defun ssa_inline_shift_reference (reference position amount)
  (declare (type usize reference position amount) (returns usize))
  (if (< reference position) reference (wrap+ reference amount)))

(defun ssa_inline_move_values (arena index position amount)
  (declare (type (ptr native_ssa_arena) arena) (type usize index position amount) (returns c-int))
  (if (< index position) 1
      (progn
        (ssa_move_record (ptr-cast (ptr u8) (ssa_value_at arena (wrap+ index amount)))
                         (ptr-cast (ptr u8) (ssa_value_at arena index)) (sizeof 'native_ssa_value))
        (ssa_inline_move_values arena (wrap- index 1) position amount))))

(defun ssa_inline_shift_value (value position amount)
  (declare (type (ptr native_ssa_value) value) (type usize position amount) (returns c-int))
  (store (field-pointer value 'left)
         (ssa_inline_shift_reference (deref (field-pointer value 'left)) position amount))
  (store (field-pointer value 'right)
         (ssa_inline_shift_reference (deref (field-pointer value 'right)) position amount))
  ;; A predecessor link entering this call now enters the first clone.
  (if (= (deref (field-pointer value 'next)) position) (wrap-cast usize 0)
      (store (field-pointer value 'next)
             (ssa_inline_shift_reference (deref (field-pointer value 'next)) position amount)))
  1)

(defun ssa_inline_shift_values (arena index count position amount)
  (declare (type (ptr native_ssa_arena) arena) (type usize index count position amount)
           (returns c-int))
  (if (< count index) 1
      (let ((mapped (ssa_inline_shift_reference index position amount)))
        (let ((value (ssa_value_at arena mapped)))
          (ssa_inline_shift_value value position amount)
          (ssa_record_type arena mapped value)
          (ssa_inline_shift_values arena (wrap+ index 1) count position amount)))))

(defun ssa_inline_shift_blocks (arena index position amount)
  (declare (type (ptr native_ssa_arena) arena) (type usize index position amount) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 1
      (let ((block (ssa_block_at arena index)))
        (if (= (deref (field-pointer block 'first)) position) (wrap-cast usize 0)
            (store (field-pointer block 'first)
                   (ssa_inline_shift_reference (deref (field-pointer block 'first)) position amount)))
        (store (field-pointer block 'last)
               (ssa_inline_shift_reference (deref (field-pointer block 'last)) position amount))
        (store (field-pointer block 'condition)
               (ssa_inline_shift_reference (deref (field-pointer block 'condition)) position amount))
        (store (field-pointer block 'result)
               (ssa_inline_shift_reference (deref (field-pointer block 'result)) position amount))
        (ssa_inline_shift_blocks arena (wrap+ index 1) position amount))))

(defun ssa_inline_reserve_values (arena position amount)
  (declare (type (ptr native_ssa_arena) arena) (type usize position amount) (returns c-int))
  (let ((count (deref (field-pointer arena 'value_count))))
    (ssa_inline_move_values arena count position amount)
    (ssa_inline_shift_values arena 1 count position amount)
    (ssa_inline_shift_blocks arena 1 position amount)
    (store (field-pointer arena 'value_count) (wrap+ count amount))
    1))
