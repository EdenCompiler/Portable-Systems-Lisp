(defpackage #:psl.source.hidden (:use #:cl) (:intern #:hidden))
(defun answer () (declare (returns u64) (c-export :c)) psl.source.hidden:hidden)
