(eval-when (:compile-toplevel)
  (defmacro build-time-add (value)
    (list 'wrap+ value 37))
  (defmacro build-time-identity (value) value))

(eval-when (:compile-toplevel))

(defun build_time_eval_when_value ()
  (declare (returns u64) (c-export :c))
  (build-time-identity (build-time-add 5)))

(eval-when (:compile-toplevel)
  (defmacro build-time-add (value)
    (list 'wrap+ value 7)))

(defun build_time_eval_when_redefined ()
  (declare (returns u64) (c-export :c))
  (build-time-add 5))
