(defpackage #:loader-missing (:use #:cl) (:import-from #:psl #:include) (:export #:include))
(loader-missing:include "absent-loader-file.lisp")
