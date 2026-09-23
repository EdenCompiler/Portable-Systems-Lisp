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
  (:export #:fail #:source-location #:make-source-location
           #:source-location-path #:source-location-line
           #:source-location-column #:location-label #:*source-location*))

(defpackage #:psl.ir
  (:use #:cl #:psl.common)
  (:export #:signature #:make-signature #:signature-name #:signature-arguments
           #:signature-result #:signature-external-p
           #:function-def #:make-function-def #:function-def-signature
           #:function-def-parameters #:function-def-body #:function-def-source
           #:hir #:make-hir #:hir-kind #:hir-type #:hir-value #:hir-children
           #:hir-source
           #:integer-type-p #:signed-type-p #:type-width #:pointer-type-p
           #:pointed-type #:pointer-const-p #:pointer-volatile-p
           #:ssa-instruction #:make-ssa-instruction #:ssa-instruction-id
           #:ssa-instruction-op #:ssa-instruction-type #:ssa-instruction-value
           #:ssa-instruction-args #:ssa-instruction-source
           #:ssa-terminator #:make-ssa-terminator #:ssa-terminator-op
           #:ssa-terminator-args #:ssa-terminator-targets
           #:ssa-terminator-source
           #:ssa-block #:make-ssa-block #:ssa-block-id
           #:ssa-block-instructions #:ssa-block-terminator
           #:ssa-function #:make-ssa-function #:ssa-function-name
           #:ssa-function-signature #:ssa-function-blocks
           #:ssa-function-entry #:ssa-function-next-value
           #:find-block #:block-successors #:block-predecessors
           #:ssa-definitions
           #:verify-hir-function #:verify-ssa-function #:verify-lir-function
           #:inline-simple-functions #:fold-constants
           #:eliminate-dead-code #:optimize-functions
           #:dump-hir-function #:dump-ssa-function #:dump-lir-function
           #:lower-function #:linearize-function
           #:lir-function #:make-lir-function #:lir-function-name
           #:lir-function-signature #:lir-function-instructions
           #:lir-function-register-count #:lir-instruction-op
           #:lir-instruction-dst #:lir-instruction-value
           #:lir-instruction-args #:lir-instruction-type
           #:lir-instruction-source #:make-lir-instruction))

(defpackage #:psl.binary
  (:use #:cl #:psl.common)
  (:export #:byte-buffer #:emit-byte #:emit-integer #:emit-bytes #:patch-i32))

(defpackage #:psl.target
  (:use #:cl #:psl.common)
  (:export #:resolve-target #:target-architecture #:target-abi
           #:target-system #:target-object-format #:target-pointer-bits
           #:target-endianness #:backend-contract
           #:resolve-backend-contract #:backend-contract-architecture
           #:backend-contract-abi #:backend-contract-object-format
           #:backend-contract-pointer-bits #:backend-contract-endianness
           #:backend-contract-argument-registers
           #:backend-contract-elf-machine
           #:backend-contract-call-relocation
           #:backend-contract-stack-alignment))

(defpackage #:psl.frontend
  (:use #:cl #:psl.common #:psl.ir #:psl.target)
  (:export #:read-source #:analyze-source))

(defpackage #:psl.ffi.toolchain
  (:use #:cl #:psl.common #:psl.target)
  (:export #:emit-with-c-sources))

(defpackage #:psl.backend.x86-64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.target)
  (:export #:compile-function #:make-relocation #:relocation-name
           #:relocation-offset #:encoded-function-name
           #:encoded-function-bytes #:encoded-function-relocations))

(defpackage #:psl.object.elf64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.backend.x86-64
        #:psl.target)
  (:export #:write-elf-object))

(defpackage #:psl.compiler
  (:use #:cl #:psl.common #:psl.ir #:psl.frontend #:psl.backend.x86-64
        #:psl.object.elf64 #:psl.target #:psl.ffi.toolchain)
  (:export #:compile-source #:*last-hir*
           #:source-unit #:read-unit #:dispose-unit #:analyze-unit
           #:lower-unit #:optimize-unit #:linearize-unit #:emit-unit
           #:compilation #:compilation-hir-functions
           #:compilation-ssa-functions #:compilation-lir-functions
           #:compilation-target #:compilation-signatures #:dump-stage))
