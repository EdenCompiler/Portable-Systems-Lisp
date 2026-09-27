;; Native target IDs select explicit architecture/ABI/OS/object combinations.
;; Zero preserves the original x86-64 Linux library API default.

(defun native_target_valid_p (target)
  (declare (type u32 target) (returns c-int))
  (if (< target 3) 1 0))

(defun native_target_architecture (target)
  (declare (type u32 target) (returns u32))
  (wrap+ target 1)) ; x86-64 / AArch64 / RISC-V64

(defun native_target_abi (target)
  (declare (type u32 target) (returns u32))
  (wrap+ target 1)) ; SysV AMD64 / AAPCS64 / LP64D

(defun native_target_object_format (target)
  (declare (type u32 target) (returns u32))
  (wrap-cast u32 1)) ; ELF64

(defun native_target_os (target)
  (declare (type u32 target) (returns u32))
  (wrap-cast u32 1)) ; Linux

(defun native_target_elf_machine (target)
  (declare (type u32 target) (returns u16))
  (cond
    ((= target 0) 62)
    ((= target 1) 183)
    (t 243)))

(defun native_target_elf_flags (target)
  (declare (type u32 target) (returns u32))
  (if (= target 2) 4 (wrap-cast u32 0))) ; LP64D, no compressed instructions
