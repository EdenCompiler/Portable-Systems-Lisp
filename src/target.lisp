(in-package #:psl.target)

(defstruct target architecture abi system object-format pointer-bits endianness)
(defstruct backend-contract architecture abi object-format pointer-bits
           endianness argument-registers float-argument-registers
           elf-machine call-relocation
           stack-alignment)

(defun c-integer-type (target name)
  (unless (member (target-abi target) '(:sysv-amd64 :win64))
    (fail "C integer aliases are not defined for ABI ~A" (target-abi target)))
  (if (member name '(psl:c-long psl:c-ulong))
      (if (eq (target-abi target) :win64)
          (if (eq name 'psl:c-long) :s32 :u32)
          (if (eq name 'psl:c-long) :s64 :u64))
      (cdr (assoc name '((psl:c-char . :s8) (psl:c-uchar . :u8)
                     (psl:c-short . :s16) (psl:c-ushort . :u16)
                     (psl:c-int . :s32) (psl:c-uint . :u32)
                     (psl:c-long-long . :s64) (psl:c-ulong-long . :u64)
                     (psl:c-size-t . :usize) (psl:c-ptrdiff-t . :isize))))))

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
    ((equal name "x86_64-windows-gnu")
     (make-target :architecture :x86-64 :abi :win64
                  :system :windows :object-format :coff
                  :pointer-bits 64 :endianness :little))
    (t (fail "unsupported target ~A" name))))

(defun resolve-backend-contract (target)
  (unless (and (eq (target-architecture target) :x86-64)
               (or (and (eq (target-abi target) :sysv-amd64)
                        (eq (target-object-format target) :elf64))
                   (and (eq (target-abi target) :win64)
                        (eq (target-object-format target) :coff)))
               (= (target-pointer-bits target) 64)
               (eq (target-endianness target) :little))
    (fail "no backend contract for architecture ~A, ABI ~A, and format ~A"
          (target-architecture target) (target-abi target)
          (target-object-format target)))
  (ecase (target-abi target)
    (:sysv-amd64
     (make-backend-contract
      :architecture :x86-64 :abi :sysv-amd64 :object-format :elf64
      :pointer-bits 64 :endianness :little
      :argument-registers '(7 6 2 1 8 9)
      :float-argument-registers '(0 1 2 3 4 5 6 7)
      :elf-machine 62 :call-relocation 4 :stack-alignment 16))
    (:win64
     (make-backend-contract
      :architecture :x86-64 :abi :win64 :object-format :coff
      :pointer-bits 64 :endianness :little
      :argument-registers '(1 2 8 9)
      :float-argument-registers '(0 1 2 3)
      :stack-alignment 16))))
