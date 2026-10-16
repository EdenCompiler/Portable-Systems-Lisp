;; Runtime module roots found in caller-provided link inputs are combined with
;; the compiler's own module mask here. Dependency closure stays in PSL.
(defun native_runtime_add_dependencies (modules roots selected dependencies)
  (declare (type u64 modules roots selected dependencies) (returns u64))
  (if (< 0 (bits-and roots selected))
      (wrap+ modules (wrap- dependencies (bits-and modules dependencies)))
      modules))

(defun native_runtime_mask_union (left right)
  (declare (type u64 left right) (returns u64))
  (wrap+ left (wrap- right (bits-and left right))))

(defun native_runtime_link_dependencies (roots)
  (declare (type u64 roots) (returns u64))
  (native_runtime_add_dependencies
  (native_runtime_add_dependencies
   (native_runtime_add_dependencies
    (native_runtime_add_dependencies
     (native_runtime_add_dependencies
      (native_runtime_add_dependencies
       (native_runtime_add_dependencies
        (native_runtime_add_dependencies
         (native_runtime_add_dependencies
          (native_runtime_add_dependencies roots roots 2 898)
          roots 4 896)
         roots 8 900)
        roots 16 908)
       roots 32 896)
      roots 64 896)
     roots 128 896)
    roots 256 512)
   roots 512 512)
   roots 1024 896))
