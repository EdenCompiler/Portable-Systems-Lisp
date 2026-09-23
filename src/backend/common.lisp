(in-package #:psl.backend)

(defstruct relocation offset name kind)
(defstruct encoded-function name bytes relocations frame-size)
