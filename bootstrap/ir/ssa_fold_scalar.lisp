(include "integer_types.lisp")

;; Fold in the target word representation. Signed narrow values are sign-extended.
(defun fold_scalar_word (code value)
  (declare (type u32 code) (type u64 value) (returns u64))
  (let ((bits (scalar_type_bits code)))
    (let ((limit (scalar_unsigned_limit bits)))
      (let ((low (bits-and value limit)))
        (if (= (scalar_type_signed_p code) 1)
            (if (< (scalar_signed_magnitude_limit bits 0) low)
                (wrap- low (wrap+ limit 1)) low)
            low)))))

(defun fold_scalar_less (code left right)
  (declare (type u32 code) (type u64 left right) (returns u64))
  (if (= (scalar_type_signed_p code) 1)
      (if (< (wrap-cast s64 left) (wrap-cast s64 right)) 1 0)
      (if (< left right) 1 0)))

(defun fold_scalar_binary (kind code left right)
  (declare (type u32 kind code) (type u64 left right) (returns u64))
  (cond
    ((= kind 4) (fold_scalar_word code (wrap+ left right)))
    ((= kind 5) (fold_scalar_word code (wrap- left right)))
    ((= kind 6) (fold_scalar_word code (wrap* left right)))
    ((= kind 11) (bits-and left right))
    ((= kind 12) (shr64 left right))
    ((= kind 8) (if (= left right) 1 0))
    (t (fold_scalar_less code left right))))
