(let ((root (make-pathname :name nil :type nil :defaults *load-truename*)))
  (dolist (file '("package.lisp"
                  "common.lisp"
                  "ir/hir.lisp"
                  "ir/types.lisp"
                  "binary.lisp"
                  "target.lisp"
                  "frontend/layout.lisp"
                  "frontend/reader.lisp"
                  "frontend/analyze.lisp"
                  "ir/lower.lisp"
                  "backend/x86-64.lisp"
                  "object/elf64.lisp"
                  "ffi/toolchain.lisp"
                  "driver.lisp"))
    (load (merge-pathnames file root))))
