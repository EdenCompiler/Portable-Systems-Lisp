(defpackage #:psl
  (:use #:cl)
  (:shadow #:load #:export)
  (:export #:defun/c #:extern-function #:wrap+ #:wrap- #:wrap* #:bits-and
           #:shr64 #:wrap-cast #:while #:include #:u64 #:s64
           #:u8 #:u16 #:u32 #:s8 #:s16 #:s32 #:usize #:isize
           #:ptr #:load #:deref #:store #:pointer+ #:ptr-cast #:ptr-from-address
           #:defstruct/packed #:defcstruct #:field-pointer #:sizeof #:alignof #:offset-of
           #:c-char #:c-uchar #:c-short #:c-ushort #:c-int #:c-uint
           #:c-long #:c-ulong #:c-long-long #:c-ulong-long
           #:c-size-t #:c-ptrdiff-t
           #:f32 #:f64 #:c-float #:c-double #:void
           #:returns #:export #:c-export #:without-allocation
           #:value #:box-fixnum #:unbox-fixnum #:make-byte-string
           #:string-byte #:set-string-byte #:make-package-from-name
           #:intern-symbol #:collect-garbage))

(defpackage #:psl.ffi
  (:nicknames #:ffi)
  (:use)
  (:export #:source #:import-function #:call #:import-data #:export-data
           #:address-of))

(defpackage #:psl.common
  (:use #:cl)
  (:export #:fail #:source-location #:make-source-location
           #:source-location-path #:source-location-line
           #:source-location-column #:location-label #:*source-location*))

(defpackage #:psl.ir
  (:use #:cl #:psl.common)
  (:export #:signature #:make-signature #:signature-name #:signature-arguments
           #:signature-result #:signature-external-p #:signature-effect
           #:signature-local-p
           #:function-def #:make-function-def #:function-def-signature
           #:function-def-parameters #:function-def-body #:function-def-source
           #:hir #:make-hir #:hir-kind #:hir-type #:hir-value #:hir-children
           #:hir-source
           #:data-declaration #:make-data-declaration #:data-declaration-name
           #:data-declaration-type #:data-declaration-size
           #:data-declaration-alignment #:data-declaration-initial
           #:data-declaration-external-p
           #:integer-type-p #:float-type-p #:signed-type-p #:type-width #:pointer-type-p
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
  (:export #:byte-buffer #:emit-byte #:emit-integer #:emit-bytes #:patch-i32
           #:float-bits))

(defpackage #:psl.target
  (:use #:cl #:psl.common)
  (:export #:resolve-target #:target-architecture #:target-abi
           #:target-system #:target-object-format #:target-pointer-bits
           #:target-endianness #:backend-contract
           #:resolve-backend-contract #:backend-contract-architecture
           #:backend-contract-abi #:backend-contract-object-format
           #:backend-contract-pointer-bits #:backend-contract-endianness
           #:backend-contract-argument-registers
           #:backend-contract-float-argument-registers
           #:backend-contract-elf-machine
           #:backend-contract-call-relocation
           #:backend-contract-stack-alignment #:c-integer-type))

(defpackage #:psl.frontend
  (:use #:cl #:psl.common #:psl.ir #:psl.target)
  (:export #:read-source #:analyze-source))

(defpackage #:psl.ffi.toolchain
  (:use #:cl #:psl.common #:psl.target)
  (:export #:emit-with-c-sources #:link-source-artifact
           #:link-freestanding-artifact))

(defpackage #:psl.backend
  (:use #:cl)
  (:export #:make-relocation #:relocation-name #:relocation-offset
           #:relocation-kind #:relocation-addend
           #:make-encoded-function #:encoded-function-name
           #:encoded-function-bytes #:encoded-function-relocations
           #:encoded-function-frame-size #:encoded-function-local-labels))

(defpackage #:psl.backend.x86-64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.target #:psl.backend)
  (:export #:compile-function #:compile-linux-exit-startup))

(defpackage #:psl.backend.aarch64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.target #:psl.backend)
  (:export #:compile-function))

(defpackage #:psl.backend.riscv64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.target #:psl.backend)
  (:export #:compile-function #:compile-qemu-virt-startup))

(defpackage #:psl.object.elf64
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.backend
        #:psl.target)
  (:export #:write-elf-object))

(defpackage #:psl.object.coff
  (:use #:cl #:psl.common #:psl.ir #:psl.binary #:psl.backend
        #:psl.target)
  (:export #:write-coff-object))

(defpackage #:psl.compiler
  (:use #:cl #:psl.common #:psl.ir #:psl.frontend #:psl.backend.x86-64
        #:psl.object.elf64 #:psl.object.coff #:psl.target #:psl.ffi.toolchain)
  (:export #:compile-source #:compile-and-link #:*last-hir*
           #:source-unit #:read-unit #:dispose-unit #:analyze-unit
           #:lower-unit #:optimize-unit #:linearize-unit #:emit-unit
           #:compilation #:compilation-hir-functions
           #:compilation-ssa-functions #:compilation-lir-functions
           #:compilation-target #:compilation-signatures
           #:compilation-runtime-modules #:dump-stage))
