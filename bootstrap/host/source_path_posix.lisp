;; POSIX hosted path services are isolated from source traversal so the same
;; loader can run on hosts with different path rules.
(ffi:import-function "realpath"
  ((path (ptr u8)) (resolved (ptr u8))) -> (ptr u8))

(defun native_source_canonical_path (path)
  (declare (type (ptr u8) path) (returns (ptr u8)) (c-export :c))
  (ffi:call realpath path (ptr-from-address (ptr u8) 0)))

(defun native_source_windows_paths ()
  (declare (returns c-int) (c-export :c))
  0)
