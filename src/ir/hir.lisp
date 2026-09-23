(in-package #:psl.ir)

(defstruct signature name arguments result external-p)
(defstruct function-def signature parameters body source)
(defstruct hir kind type value children source)
(defstruct data-declaration name type size alignment initial external-p)
