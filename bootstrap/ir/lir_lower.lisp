;; SSA -> LIR resolves PHIs on incoming edges. Branches get explicit edge
;; labels, so copies are correct even when an edge needs its own block.

(defun lir_lower_value (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (let ((ssa (deref (field-pointer context 'ssa)))
        (lir (deref (field-pointer context 'lir))))
    (let ((value (ssa_value_at ssa reference)))
      (let ((kind (deref (field-pointer value 'kind))))
        (if (= kind 28) 1
            (if (= kind 17) 1
                (let ((result (lir_allocate lir kind reference (deref (field-pointer value 'left))
                                            (deref (field-pointer value 'right))
                                            (deref (field-pointer value 'target)))))
                  (if (= result 0) 0
                      (progn
                        (store (field-pointer (lir_instruction_at lir result) 'value)
                               (deref (field-pointer value 'value)))
                        (lir_record_type lir result (deref (field-pointer value 'scalar_code))
                                         (deref (field-pointer value 'pointee))
                                         (deref (field-pointer value 'source))))))))))))

(defun lir_lower_values (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns c-int))
  (if (= reference 0) 1
      (if (= (lir_lower_value context reference) 0) 0
          (lir_lower_values context (deref (field-pointer
                                            (ssa_value_at (deref (field-pointer context 'ssa)) reference) 'next))))))

(defun lir_lower_edge_copies (context predecessor reference)
  (declare (type (ptr native_compile_context) context)
           (type usize predecessor reference) (returns c-int))
  (if (= reference 0) 1
      (let ((value (ssa_value_at (deref (field-pointer context 'ssa)) reference)))
        (if (= (deref (field-pointer value 'kind)) 28)
            (let ((incoming (if (= predecessor (deref (field-pointer value 'predecessor_left)))
                                (deref (field-pointer value 'left))
                                (deref (field-pointer value 'right))))
                  (lir (deref (field-pointer context 'lir))))
              (let ((copy (lir_allocate lir 104 reference incoming 0 0)))
                (if (= (lir_record_type lir copy (deref (field-pointer value 'scalar_code))
                                        (deref (field-pointer value 'pointee))
                                        (deref (field-pointer value 'source))) 0) 0
                    (lir_lower_edge_copies context predecessor (deref (field-pointer value 'next))))))
            1))))

(defun lir_lower_edge (context predecessor successor)
  (declare (type (ptr native_compile_context) context)
           (type usize predecessor successor) (returns c-int))
  (let ((block (ssa_block_at (deref (field-pointer context 'ssa)) successor)))
    (if (= (lir_lower_edge_copies context predecessor (deref (field-pointer block 'first))) 0) 0
        (if (= (lir_allocate (deref (field-pointer context 'lir)) 101 0 0 0 successor) 0) 0 1))))

(defun lir_lower_branch_edges (context predecessor block)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ssa_block) block)
           (type usize predecessor) (returns c-int))
  (let ((lir (deref (field-pointer context 'lir))))
    (let ((left (wrap+ (deref (field-pointer lir 'label_count)) 1))
          (right (wrap+ (deref (field-pointer lir 'label_count)) 2)))
      (if (< (deref (field-pointer lir 'label_capacity)) right) 0
          (progn
            (store (field-pointer lir 'label_count) right)
            (if (= (lir_allocate lir 102 0 (deref (field-pointer block 'condition)) right left) 0) 0
                (if (= (lir_allocate lir 100 0 0 0 left) 0) 0
                    (if (= (lir_lower_edge context predecessor (deref (field-pointer block 'target_left))) 0) 0
                        (if (= (lir_allocate lir 100 0 0 0 right) 0) 0
                            (lir_lower_edge context predecessor (deref (field-pointer block 'target_right))))))))))))

(defun lir_lower_terminator (context block index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_ssa_block) block)
           (type usize index) (returns c-int))
  (let ((lir (deref (field-pointer context 'lir))))
    (cond
      ((= (deref (field-pointer block 'terminator)) 2)
       (lir_lower_edge context index (deref (field-pointer block 'target_left))))
      ((= (deref (field-pointer block 'terminator)) 3)
       (lir_lower_branch_edges context index block))
      (t (let ((result (deref (field-pointer block 'result)))
               (types (deref (field-pointer lir 'types))))
           (let ((type (ir_type_at types result))
                 (return (lir_allocate lir 103 0 result 0 0)))
             (lir_record_type lir return (deref (field-pointer type 'scalar_code))
                              (deref (field-pointer type 'pointee)) 1)))))))

(defun lir_lower_blocks (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index) (returns c-int))
  (let ((ssa (deref (field-pointer context 'ssa)))
        (lir (deref (field-pointer context 'lir))))
    (if (< (deref (field-pointer ssa 'block_count)) index) 1
        (let ((block (ssa_block_at ssa index)))
          (if (= (lir_allocate lir 100 0 0 0 index) 0) 0
              (if (= (lir_lower_values context (deref (field-pointer block 'first))) 0) 0
                  (if (= (lir_lower_terminator context block index) 0) 0
                      (lir_lower_blocks context (wrap+ index 1)))))))))

(defun lir_lower_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((ssa (deref (field-pointer context 'ssa)))
        (lir (deref (field-pointer context 'lir))))
    (store (field-pointer lir 'count) 0)
    (store (field-pointer lir 'error) 0)
    (store (field-pointer lir 'types) (deref (field-pointer ssa 'types)))
    (store (field-pointer lir 'value_count) (deref (field-pointer ssa 'value_count)))
    (store (field-pointer lir 'label_count) (deref (field-pointer ssa 'block_count)))
    (lir_lower_blocks context 1)))
