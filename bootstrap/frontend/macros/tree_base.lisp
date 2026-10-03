(include "tree_types.lisp")
(include "../parser.lisp")

(defun native_tree_fail (context code)
  (declare (type (ptr native_tree_context) context) (type u32 code)
           (returns usize))
  (if (= (deref (field-pointer context 'error)) 0)
      (store (field-pointer context 'error) code) (wrap-cast u32 0))
  0)

