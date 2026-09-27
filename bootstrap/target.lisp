;; Native target IDs select explicit architecture/ABI/OS/object combinations.
;; Zero preserves the original x86-64 Linux library API default.

(defun native_target_valid_p (target)
  (declare (type u32 target) (returns c-int))
  (if (< target 2) 1 0))

(defun native_target_architecture (target)
  (declare (type u32 target) (returns u32))
  (if (= target 0) 1 (wrap-cast u32 2))) ; x86-64 / AArch64

(defun native_target_abi (target)
  (declare (type u32 target) (returns u32))
  (if (= target 0) 1 (wrap-cast u32 2))) ; SysV AMD64 / AAPCS64

(defun native_target_object_format (target)
  (declare (type u32 target) (returns u32))
  (wrap-cast u32 1)) ; ELF64

(defun native_target_os (target)
  (declare (type u32 target) (returns u32))
  (wrap-cast u32 1)) ; Linux

(defun native_target_elf_machine (target)
  (declare (type u32 target) (returns u16))
  (if (= (native_target_architecture target) 1) 62 (wrap-cast u16 183)))
