;; Scalar operation shape checks precede type-table access in both IRs.

(defun ir_reference_p (reference count)
  (declare (type usize reference count) (returns c-int))
  (if (= reference 0) 0 (if (< count reference) 0 1)))

(defun ir_binary_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (cond
    ((= kind 4) 1) ((= kind 5) 1) ((= kind 6) 1)
    ((= kind 8) 1) ((= kind 9) 1) ((= kind 11) 1) ((= kind 12) 1)
    ((= kind 25) 1) ((= kind 27) 1) ((= kind 28) 1)
    (t 0)))

(defun ir_leaf_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (if (= kind 1) 1 (if (= kind 2) 1 (if (= kind 19) 1 0))))

(defun ir_unary_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (cond
    ((= kind 18) 1) ((= kind 20) 1) ((= kind 21) 1)
    ((= kind 22) 1) ((= kind 23) 1) ((= kind 24) 1)
    ((= kind 104) 1)
    (t 0)))

(defun ir_op_operands_p (op count)
  (declare (type (ptr native_scalar_op) op)
           (type usize count) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (left (deref (field-pointer op 'left)))
        (right (deref (field-pointer op 'right))))
    (cond
      ((= (ir_leaf_kind_p kind) 1) (if (= left 0) (if (= right 0) 1 0) 0))
      ((= (ir_unary_kind_p kind) 1) (if (= right 0) (ir_reference_p left count) 0))
      ((= (ir_binary_kind_p kind) 1)
       (if (= (ir_reference_p left count) 0) 0 (ir_reference_p right count)))
      ((= kind 7) (if (= right 0) (if (= left 0) 1 (ir_reference_p left count)) 0))
      ((= kind 17)
       (if (= (ir_reference_p left count) 0) 0
           (if (= right 0) 1 (ir_reference_p right count))))
      (t 0))))

(defun ir_op_metadata_p (context op)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_scalar_op) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind)))
        (target (deref (field-pointer op 'target)))
        (value (deref (field-pointer op 'value))))
    (if (= (source_type_reference_p context (deref (field-pointer op 'source))) 0) 0
        (cond
          ((= kind 7)
           (if (= value 0) (ir_reference_p target (deref (field-pointer context 'prior_count))) 0))
          ((= kind 23) (if (= target 0) 0 1))
          ((= target 0)
           (cond
             ((= (ir_leaf_kind_p kind) 1) 1)
             ((= kind 24) (if (= value 1) 1 (if (= value 2) 1 (if (= value 4) 1 (if (= value 8) 1 0)))))
             ((= kind 25) (if (= value 1) 1 (if (= value 2) 1 (if (= value 4) 1 (if (= value 8) 1 0)))))
             ((= kind 27) (if (= value 0) 0 1))
             (t (if (= value 0) 1 0))))
          (t 0)))))
