(defpackage #:loader-order (:use #:cl) (:import-from #:psl #:include))
(in-package #:loader-order)
(include "child files/select-package.lisp")
(include "valid-leaf.lisp")
