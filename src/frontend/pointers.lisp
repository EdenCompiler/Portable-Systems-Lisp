(in-package #:psl.frontend)

(defun analyze-pointer-address (form environment context)
  (unless (= (length form) 2)
    (fail "PTR-ADDRESS requires one raw pointer"))
  (let ((pointer (analyze-expression (second form) environment context)))
    (unless (pointer-type-p (hir-type pointer))
      (fail "PTR-ADDRESS requires a raw pointer"))
    (make-hir :kind :pointer-address :type :usize :children (list pointer))))
