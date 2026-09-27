;; Keep SSA IDs and proof records stable; omit unmarked definitions in LIR.
;; Loads remain roots until native memory qualifiers/effects are ported.

(defun ssa_effect_root_p (kind)
  (declare (type u32 kind) (returns c-int))
  (if (= kind 7) 1 (if (= kind 24) 1 (if (= kind 25) 1 0))))

(defun ssa_set_liveness (arena live index)
  (declare (type (ptr native_ssa_arena) arena) (type c-int live)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'value_count)) index) 1
      (progn
        (store (field-pointer (ssa_value_at arena index) 'live) live)
        (ssa_set_liveness arena live (wrap+ index 1)))))

(defun ssa_mark_live (arena reference)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference) (returns c-int))
  (if (= reference 0) 1
      (let ((value (ssa_value_at arena reference)))
        (if (= (deref (field-pointer value 'live)) 1) 1
            (progn
              (store (field-pointer value 'live) 1)
              (ssa_mark_live arena (deref (field-pointer value 'left)))
              (ssa_mark_live arena (deref (field-pointer value 'right))))))))

(defun ssa_mark_effects (arena reference)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference) (returns c-int))
  (if (< (deref (field-pointer arena 'value_count)) reference) 1
      (progn
        (if (= (ssa_effect_root_p (deref (field-pointer (ssa_value_at arena reference) 'kind))) 1)
            (ssa_mark_live arena reference) (wrap-cast c-int 1))
        (ssa_mark_effects arena (wrap+ reference 1)))))

(defun ssa_mark_terminals (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 1
      (let ((block (ssa_block_at arena index)))
        (ssa_mark_live arena (deref (field-pointer block 'condition)))
        (ssa_mark_live arena (deref (field-pointer block 'result)))
        (ssa_mark_terminals arena (wrap+ index 1)))))

(defun ssa_eliminate_dead_values (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (ssa_set_liveness arena 0 1)
    (ssa_mark_terminals arena 1)
    (ssa_mark_effects arena 1)))

(defun ssa_reference_live_p (arena reference)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference) (returns c-int))
  (if (= reference 0) 1
      (if (= (deref (field-pointer (ssa_value_at arena reference) 'live)) 1) 1 0)))

(defun ssa_verify_live_values (arena reference)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference) (returns c-int))
  (if (< (deref (field-pointer arena 'value_count)) reference) 1
      (let ((value (ssa_value_at arena reference)))
        (let ((live (deref (field-pointer value 'live))))
          (if (= live 0)
              (if (= (ssa_effect_root_p (deref (field-pointer value 'kind))) 1) 0
                  (ssa_verify_live_values arena (wrap+ reference 1)))
              (if (= live 1)
                  (if (= (ssa_reference_live_p arena (deref (field-pointer value 'left))) 0) 0
                      (if (= (ssa_reference_live_p arena (deref (field-pointer value 'right))) 0) 0
                          (ssa_verify_live_values arena (wrap+ reference 1)))) 0))))))

(defun ssa_verify_live_terminals (arena index)
  (declare (type (ptr native_ssa_arena) arena) (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'block_count)) index) 1
      (let ((block (ssa_block_at arena index)))
        (if (= (ssa_reference_live_p arena (deref (field-pointer block 'condition))) 0) 0
            (if (= (ssa_reference_live_p arena (deref (field-pointer block 'result))) 0) 0
                (ssa_verify_live_terminals arena (wrap+ index 1)))))))

(defun ssa_verify_liveness (context)
  (declare (type (ptr native_compile_context) context) (returns c-int) (c-export :c))
  (if (= (ssa_verify_function context) 0) 0
      (let ((arena (deref (field-pointer context 'ssa))))
        (if (= (ssa_verify_live_values arena 1) 0) 0
            (ssa_verify_live_terminals arena 1)))))
