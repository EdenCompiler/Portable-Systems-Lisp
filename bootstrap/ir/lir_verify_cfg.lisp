;; Build and verify LIR blocks from the flat label stream. Every block has one
;; final terminator; all labels are unique and reachable from entry label 1.

(defun lir_clear_blocks (arena index)
  (declare (type (ptr native_lir_arena) arena)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'label_count)) index) 1
      (let ((block (lir_block_at arena index)))
        (store (field-pointer block 'first) 0)
        (store (field-pointer block 'last) 0)
        (store (field-pointer block 'visit) 0)
        (lir_clear_blocks arena (wrap+ index 1)))))

(defun lir_scan_blocks (arena instruction previous)
  (declare (type (ptr native_lir_arena) arena)
           (type usize instruction previous) (returns c-int))
  (if (< (deref (field-pointer arena 'count)) instruction)
      (if (= previous 0) 0
          (progn (store (field-pointer (lir_block_at arena previous) 'last)
                        (deref (field-pointer arena 'count))) 1))
      (let ((op (lir_instruction_at arena instruction)))
        (if (= (deref (field-pointer op 'kind)) 100)
            (let ((label (deref (field-pointer op 'target))))
              (if (= (ir_reference_p label (deref (field-pointer arena 'label_count))) 0) 0
                  (let ((block (lir_block_at arena label)))
                    (if (= (deref (field-pointer block 'first)) 0)
                        (progn
                          (store (field-pointer block 'first) (wrap+ instruction 1))
                          (if (= previous 0) (wrap-cast usize 0)
                              (store (field-pointer (lir_block_at arena previous) 'last) (wrap- instruction 1)))
                          (lir_scan_blocks arena (wrap+ instruction 1) label)) 0))))
            (if (= previous 0) 0 (lir_scan_blocks arena (wrap+ instruction 1) previous))))))

(defun lir_terminal_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (if (= kind 101) 1 (if (= kind 102) 1 (if (= kind 103) 1 0))))

(defun lir_verify_block_range (arena first last)
  (declare (type (ptr native_lir_arena) arena)
           (type usize first last) (returns c-int))
  (if (= (ir_reference_p last (deref (field-pointer arena 'count))) 0) 0
      (if (< last first) 0
          (let ((kind (deref (field-pointer (lir_instruction_at arena first) 'kind))))
            (if (= first last) (lir_terminal_kind_p kind)
                (if (= (lir_terminal_kind_p kind) 1) 0
                    (lir_verify_block_range arena (wrap+ first 1) last)))))))

(defun lir_verify_ranges (arena index)
  (declare (type (ptr native_lir_arena) arena)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'label_count)) index) 1
      (let ((block (lir_block_at arena index)))
        (if (= (deref (field-pointer block 'first)) 0) 0
            (if (= (lir_verify_block_range arena (deref (field-pointer block 'first))
                                           (deref (field-pointer block 'last))) 0) 0
                (lir_verify_ranges arena (wrap+ index 1)))))))

(defun lir_clear_visits (arena index)
  (declare (type (ptr native_lir_arena) arena)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'label_count)) index) 1
      (progn (store (field-pointer (lir_block_at arena index) 'visit) 0)
             (lir_clear_visits arena (wrap+ index 1)))))

(defun lir_block_defines_p (arena value first last)
  (declare (type (ptr native_lir_arena) arena)
           (type usize value first last) (returns c-int))
  (if (< last first) 0
      (if (= (deref (field-pointer (lir_instruction_at arena first) 'destination)) value) 1
          (lir_block_defines_p arena value (wrap+ first 1) last))))

(defun lir_reaches_without_definition (arena current target value)
  (declare (type (ptr native_lir_arena) arena)
           (type usize current target value) (returns c-int))
  (if (= current 0) 0
      (if (= current target) 1
          (let ((block (lir_block_at arena current)))
            (if (= (deref (field-pointer block 'visit)) 1) 0
                (if (= value 0)
                    (lir_search_successors arena block target value)
                    (if (= (lir_block_defines_p arena value (deref (field-pointer block 'first))
                                                (deref (field-pointer block 'last))) 1) 0
                        (lir_search_successors arena block target value))))))))

(defun lir_search_successors (arena block target value)
  (declare (type (ptr native_lir_arena) arena)
           (type (ptr native_lir_block) block)
           (type usize target value) (returns c-int))
  (store (field-pointer block 'visit) 1)
  (let ((op (lir_instruction_at arena (deref (field-pointer block 'last)))))
    (if (= (deref (field-pointer op 'kind)) 103) 0
        (if (= (lir_reaches_without_definition arena (deref (field-pointer op 'target)) target value) 1) 1
            (if (= (deref (field-pointer op 'kind)) 102)
                (lir_reaches_without_definition arena (deref (field-pointer op 'right)) target value) 0)))))

(defun lir_value_defined_p (arena value instruction block)
  (declare (type (ptr native_lir_arena) arena)
           (type usize value instruction block) (returns c-int))
  (if (= (lir_block_defines_p arena value (deref (field-pointer (lir_block_at arena block) 'first))
                             (wrap- instruction 1)) 1) 1
      (progn
        (lir_clear_visits arena 1)
        (if (= (lir_reaches_without_definition arena 1 block value) 1) 0 1))))

(defun lir_verify_reachability (arena index)
  (declare (type (ptr native_lir_arena) arena)
           (type usize index) (returns c-int))
  (if (< (deref (field-pointer arena 'label_count)) index) 1
      (progn
        (lir_clear_visits arena 1)
        (if (= (lir_reaches_without_definition arena 1 index 0) 0) 0
            (lir_verify_reachability arena (wrap+ index 1))))))
