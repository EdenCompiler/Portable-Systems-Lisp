(defpackage #:psl.source.failure (:import-from #:cl "NONEXISTENT-SYMBOL"))
(defun answer () (declare (returns u64) (c-export :c)) 42)
