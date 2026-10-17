(defmacro oracle-nil-key (&key ((nil value) 3 supplied))
  (list 'list value supplied))
(let ((condition
        (handler-case
            (progn (macroexpand-1 '(oracle-nil-key nil 7)) nil)
          (error (condition) condition))))
  (unless (and condition (typep condition 'error))
    (error "expected raw SBCL macro expansion to signal ERROR, got ~S"
           condition))
  (format t "SBCL raw explicit NIL key without allowance: ~A~%" condition))
(let ((expansion
        (macroexpand-1 '(oracle-nil-key nil 7 :allow-other-keys t))))
  (unless (equal expansion '(list 7 t))
    (error "unexpected allowed raw NIL-key expansion: ~S" expansion))
  (format t "SBCL raw explicit NIL key with allowance: ~S~%" expansion))
