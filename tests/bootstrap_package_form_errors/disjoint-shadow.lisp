(defpackage #:psl.source.failure (:shadow "CAR") (:intern #:car))
(defun answer () (declare (returns u64) (c-export :c)) 42)
