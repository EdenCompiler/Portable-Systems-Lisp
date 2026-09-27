(include "../target.lisp")
(include "lir_emit_x86.lisp")
(include "lir_emit_aarch64.lisp")
(include "lir_emit_riscv64.lisp")

(defun native_emit_lir_function (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((target (deref (field-pointer context 'target))))
    (if (= (native_target_valid_p target) 0) 0
        (cond
          ((= (native_target_abi target) 1) (emit_lir_x86_function context))
          ((= (native_target_abi target) 2) (emit_lir_aarch64_function context))
          ((= (native_target_abi target) 3) (emit_lir_riscv64_function context))
          (t 0)))))

(defun native_patch_unit_calls (context count)
  (declare (type (ptr native_compile_context) context) (type usize count) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (functions (deref (field-pointer context 'functions)))
        (fixups (deref (field-pointer context 'fixups)))
        (target (deref (field-pointer context 'target))))
    (cond
      ((= (native_target_architecture target) 1) (patch_call_fixups code functions count fixups))
      ((= (native_target_architecture target) 2) (a64_patch_calls code functions count fixups))
      ((= (native_target_architecture target) 3) (rv_patch_calls code functions count fixups))
      (t 0))))
