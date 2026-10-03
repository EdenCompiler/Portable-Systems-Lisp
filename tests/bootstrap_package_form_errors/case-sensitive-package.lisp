(defpackage "psl.source.lower" (:use #:cl))
(in-package #:psl.source.lower)
(defun answer () (declare (returns psl:u64) (psl:c-export :c)) 42)
