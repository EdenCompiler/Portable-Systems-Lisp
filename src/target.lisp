(in-package #:psl.target)

(defstruct target architecture abi system object-format pointer-bits endianness)

(defun resolve-target (name)
  (cond
    ((equal name "x86_64-linux-gnu")
     (make-target :architecture :x86-64 :abi :sysv-amd64
                  :system :linux :object-format :elf64
                  :pointer-bits 64 :endianness :little))
    ((equal name "x86_64-none-elf")
     (make-target :architecture :x86-64 :abi :sysv-amd64
                  :system :none :object-format :elf64
                  :pointer-bits 64 :endianness :little))
    (t (fail "unsupported target ~A" name))))
