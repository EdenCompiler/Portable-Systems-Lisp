(defpackage #:psl
  (:use #:cl)
  (:shadow #:load #:export)
  (:export #:defun/c #:extern-function #:wrap+ #:wrap- #:wrap* #:u64 #:s64
           #:u8 #:u16 #:u32 #:s8 #:s16 #:s32 #:usize #:isize
           #:ptr #:load #:deref #:store #:pointer+ #:ptr-cast #:ptr-from-address
           #:defstruct/packed #:field-pointer #:sizeof #:alignof #:offset-of
           #:returns #:export #:c-export))

(defpackage #:psl.ffi
  (:nicknames #:ffi)
  (:use)
  (:export #:source #:import-function #:call))

(defpackage #:psl.common
  (:use #:cl)
  (:export #:fail))

(defpackage #:psl.ir
  (:use #:cl)
  (:export #:signature #:make-signature #:signature-name #:signature-arguments
           #:signature-result #:signature-external-p
           #:function-def #:make-function-def #:function-def-signature
           #:function-def-parameters #:function-def-body
           #:hir #:make-hir #:hir-kind #:hir-type #:hir-value #:hir-children
           #:integer-type-p #:signed-type-p #:type-width #:pointer-type-p
           #:pointed-type #:pointer-const-p #:pointer-volatile-p
           #:lower-function #:lir-function-name #:lir-function-instructions
           #:lir-function-register-count #:lir-instruction-op
           #:lir-instruction-dst #:lir-instruction-value
           #:lir-instruction-args))

(defpackage #:psl.binary
  (:use #:cl #:psl.common)
  (:export #:byte-buffer #:emit-byte #:emit-integer #:emit-bytes #:patch-i32))

(defpackage #:psl.target
  (:use #:cl #:psl.common)
  (:export #:resolve-target #:target-architecture #:target-abi
           #:target-system #:target-object-format #:target-pointer-bits
           #:target-endianness))

(defpackage #:psl.frontend
  (:use #:cl #:psl.common #:psl.ir #:psl.target)
  (:export #:read-source #:analyze-source))

(defpackage #:psl.ffi.toolchain
  (:use #:cl #:psl.common #:psl.target)
  (:export #:emit-with-c-sources))

(defpackage #:psl.backend.x86-64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary)
  (:export #:compile-function #:make-relocation #:relocation-name
           #:relocation-offset #:encoded-function-name
           #:encoded-function-bytes #:encoded-function-relocations))

(defpackage #:psl.object.elf64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.backend.x86-64)
  (:export #:write-elf-object))

(defpackage #:psl.compiler
  (:use #:cl #:psl.common #:psl.ir #:psl.frontend #:psl.backend.x86-64
        #:psl.object.elf64 #:psl.target #:psl.ffi.toolchain)
  (:export #:compile-source #:*last-hir*))
