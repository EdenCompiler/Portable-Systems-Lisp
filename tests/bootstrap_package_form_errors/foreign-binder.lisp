(defpackage #:psl.source.foreign (:use))
(defun answer (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  psl.source.foreign::value)
