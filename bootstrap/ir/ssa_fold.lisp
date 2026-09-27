(include "ssa_fold_scalar.lisp")

(defun ssa_constant_p (value)
  (declare (type (ptr native_ssa_value) value) (returns c-int))
  (let ((kind (deref (field-pointer value 'kind))))
    (if (= kind 1) 1 (if (= kind 19) 1 0))))

(defun ssa_replace_constant (arena reference value word)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference)
           (type (ptr native_ssa_value) value) (type u64 word) (returns c-int))
  (store (field-pointer value 'kind)
         (if (= (deref (field-pointer value 'scalar_code)) 0) (wrap-cast u32 19) (wrap-cast u32 1)))
  (store (field-pointer value 'value) word)
  (store (field-pointer value 'left) 0)
  (store (field-pointer value 'right) 0)
  (store (field-pointer value 'target) 0)
  (store (field-pointer value 'predecessor_left) 0)
  (store (field-pointer value 'predecessor_right) 0)
  (ssa_record_type arena reference value)
  1)

(defun ssa_fold_binary_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (cond
    ((= kind 4) 1) ((= kind 5) 1) ((= kind 6) 1)
    ((= kind 8) 1) ((= kind 9) 1) ((= kind 11) 1) ((= kind 12) 1)
    (t 0)))

(defun ssa_fold_binary (arena reference value)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference)
           (type (ptr native_ssa_value) value) (returns c-int))
  (let ((left (ssa_value_at arena (deref (field-pointer value 'left))))
        (right (ssa_value_at arena (deref (field-pointer value 'right)))))
    (if (= (ssa_constant_p left) 0) 0
        (if (= (ssa_constant_p right) 0) 0
            (ssa_replace_constant arena reference value
              (fold_scalar_binary (deref (field-pointer value 'kind))
                                  (deref (field-pointer left 'scalar_code))
                                  (deref (field-pointer left 'value))
                                  (deref (field-pointer right 'value))))))))

(defun ssa_fold_cast (arena reference value)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference)
           (type (ptr native_ssa_value) value) (returns c-int))
  (let ((child (ssa_value_at arena (deref (field-pointer value 'left)))))
    (if (= (ssa_constant_p child) 0) 0
        (ssa_replace_constant arena reference value
          (fold_scalar_word (deref (field-pointer value 'scalar_code))
                            (deref (field-pointer child 'value)))))))

(defun ssa_fold_copy (arena reference value)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference)
           (type (ptr native_ssa_value) value) (returns c-int))
  (let ((child (ssa_value_at arena (deref (field-pointer value 'left)))))
    (if (= (ssa_constant_p child) 0) 0
        (ssa_replace_constant arena reference value (deref (field-pointer child 'value))))))

;; Only fold the last PHI in a verified prefix, preserving prefix ordering.
(defun ssa_last_phi_p (arena value)
  (declare (type (ptr native_ssa_arena) arena) (type (ptr native_ssa_value) value)
           (returns c-int))
  (let ((next (deref (field-pointer value 'next))))
    (if (= next 0) 1
        (if (= (deref (field-pointer (ssa_value_at arena next) 'kind)) 28) 0 1))))

(defun ssa_fold_phi (arena reference value)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference)
           (type (ptr native_ssa_value) value) (returns c-int))
  (if (= (ssa_last_phi_p arena value) 0) 0
      (let ((left (ssa_value_at arena (deref (field-pointer value 'left))))
            (right (ssa_value_at arena (deref (field-pointer value 'right)))))
        (if (= (ssa_constant_p left) 0) 0
            (if (= (ssa_constant_p right) 0) 0
                (if (= (deref (field-pointer left 'value)) (deref (field-pointer right 'value)))
                    (ssa_replace_constant arena reference value (deref (field-pointer left 'value)))
                    0))))))

(defun ssa_fold_value (arena reference)
  (declare (type (ptr native_ssa_arena) arena) (type usize reference) (returns c-int))
  (let ((value (ssa_value_at arena reference)))
    (let ((kind (deref (field-pointer value 'kind))))
      (cond
        ((= (ssa_fold_binary_kind_p kind) 1) (ssa_fold_binary arena reference value))
        ((= kind 18) (ssa_fold_cast arena reference value))
        ((= kind 31) (ssa_fold_copy arena reference value))
        ((= kind 28) (ssa_fold_phi arena reference value))
        ;; Every integer/raw pointer is true in Lisp, including zero/null.
        ((= kind 20)
         (let ((child (ssa_value_at arena (deref (field-pointer value 'left)))))
           (if (= (deref (field-pointer child 'scalar_code)) 0) 0
               (ssa_replace_constant arena reference value 1))))
        (t 0)))))
