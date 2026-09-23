(in-package #:psl.backend)

(defstruct relocation offset name kind addend)
(defstruct encoded-function name bytes relocations frame-size local-labels)
