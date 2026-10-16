(defmacro oracle-nil-key (&key ((nil value) 3 supplied))
  (list 'list value supplied))
(handler-case
    (progn
      (macroexpand-1 '(oracle-nil-key nil 7))
      (error "expected the seed expander's NIL-key discrepancy"))
  (error (condition)
    (format t "SBCL raw explicit NIL key without allowance: ~A~%" condition)))
(format t "SBCL raw explicit NIL key with allowance: ~S~%"
        (macroexpand-1 '(oracle-nil-key nil 7 :allow-other-keys t)))
