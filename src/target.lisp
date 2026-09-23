(in-package #:psl.target)

(defstruct target architecture abi system object-format pointer-bits endianness)
(defstruct backend-contract architecture abi object-format pointer-bits
           endianness argument-registers elf-machine call-relocation
           stack-alignment)

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

(defun resolve-backend-contract (target)
  (unless (and (eq (target-architecture target) :x86-64)
               (eq (target-abi target) :sysv-amd64)
               (eq (target-object-format target) :elf64)
               (= (target-pointer-bits target) 64)
               (eq (target-endianness target) :little))
    (fail "no backend contract for architecture ~A, ABI ~A, and format ~A"
          (target-architecture target) (target-abi target)
          (target-object-format target)))
  (make-backend-contract
   :architecture :x86-64 :abi :sysv-amd64 :object-format :elf64
   :pointer-bits 64 :endianness :little
   :argument-registers '(7 6 2 1 8 9)
   :elf-machine 62 :call-relocation 4 :stack-alignment 16))
