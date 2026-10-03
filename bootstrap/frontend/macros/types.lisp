(include "tree_types.lisp")

(defcstruct native_macro_definition
  (symbol usize)
  (parameters usize)
  (body usize))

(defcstruct native_macro_registry
  (parser (ptr psl_parser))
  (source (ptr u8))
  (tree (ptr native_tree_context))
  (definitions (ptr native_macro_definition))
  (count usize)
  (capacity usize)
  (error u32))

(defcstruct native_macro_binding
  (symbol usize)
  (form usize))
(defcstruct native_macro_expansion
  (form usize)
  (expanded c-int))
(defcstruct native_macro_call
  (registry (ptr native_macro_registry))
  (bindings (ptr native_macro_binding))
  (count usize)
  (capacity usize)
  (origin usize)
  (error u32)
  (steps usize)
  (step_limit usize)
  (expansion native_macro_expansion)
  (repeated native_macro_expansion))
