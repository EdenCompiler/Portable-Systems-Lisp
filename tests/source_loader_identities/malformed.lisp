(defpackage #:loader-malformed (:use #:cl) (:import-from #:psl #:include) (:export #:include))
(loader-malformed:include "valid-leaf.lisp" "extra")
