(defpackage #:psl.source.failure (:intern "CAR") (:export #:car))
(defun answer () (declare (returns u64) (c-export :c)) 42)
