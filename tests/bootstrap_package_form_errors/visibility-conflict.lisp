(defpackage #:psl.source.conflict (:use #:cl #:psl))
(defun answer () (declare (returns u64) (c-export :c)) 42)
