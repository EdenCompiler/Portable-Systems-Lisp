(include "ssa_fold.lisp")
(include "ssa_live.lisp")

(defun ssa_fold_scan (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((arena (deref (field-pointer context 'ssa))))
    (store (field-pointer context 'fold_cursor) 1)
    (while (< (deref (field-pointer context 'fold_cursor))
              (wrap+ (deref (field-pointer arena 'value_count)) 1))
      (if (= (ssa_fold_value arena (deref (field-pointer context 'fold_cursor))) 1)
          (store (field-pointer context 'fold_changed) 1) (wrap-cast c-int 0))
      (store (field-pointer context 'fold_cursor)
             (wrap+ (deref (field-pointer context 'fold_cursor)) 1)))
    1))

(defun ssa_fold_constants (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (store (field-pointer context 'fold_changed) 1)
  (while (= (deref (field-pointer context 'fold_changed)) 1)
    (store (field-pointer context 'fold_changed) 0)
    (ssa_fold_scan context))
  1)

(defun ssa_optimize_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int) (c-export :c))
  (let ((level (deref (field-pointer context 'optimization))))
    (if (< 1 level) 0
        (if (= (ssa_verify_function context) 0) 0
            (progn
              (ssa_set_liveness (deref (field-pointer context 'ssa)) 1 1)
              (if (= level 0) 1
                  (progn
                    (ssa_fold_constants context)
                    (if (= (ssa_verify_function context) 0) 0
                        (progn (ssa_eliminate_dead_values context)
                               (ssa_verify_liveness context))))))))))
