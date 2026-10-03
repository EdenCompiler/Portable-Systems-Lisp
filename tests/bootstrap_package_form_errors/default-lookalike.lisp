(defpackage #:psl.source.default.bad)
(in-package #:psl.source.default.bad)
(cl:defun answer () (cl:declare (psl:returns psl:u64) (psl:c-export :c))
  (if 0 42 99))
