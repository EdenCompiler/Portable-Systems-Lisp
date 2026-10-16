(ffi:source "harness_bootstrap_cli_link_runtime_source.c")
(defun native_cli_answer ()
  (declare (returns u64) (c-export :c))
  42)
