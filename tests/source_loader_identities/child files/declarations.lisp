(defpackage #:loader-output (:use #:cl) (:import-from #:psl #:include))
(in-package #:loader-output)
(ld:|SOURCE| "support.c")
(ffi:import-data "loader_bias" psl:c-int)
