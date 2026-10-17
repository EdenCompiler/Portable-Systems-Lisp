(include "tree_types.lisp")

(defcstruct native_macro_registry
  (parser (ptr psl_parser))
  (source (ptr u8))
  (tree (ptr native_tree_context))
  (integer (ptr u8))
  (definition_handle usize)
  (count usize)
  (capacity usize)
  (error u32))

(defcstruct native_macro_expansion
  (form usize)
  (expanded c-int))
(defcstruct native_macro_call
  (registry (ptr native_macro_registry))
  (binding_handle usize)
  (count usize)
  (capacity usize)
  (origin usize)
  (error u32)
  (steps usize)
  (step_limit usize)
  (expansion native_macro_expansion)
  (repeated native_macro_expansion))
