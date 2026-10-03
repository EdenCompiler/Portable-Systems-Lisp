(defpackage #:psl.source.failure (:|use| #:cl))
(defun answer () (declare (returns u64) (c-export :c)) 42)
