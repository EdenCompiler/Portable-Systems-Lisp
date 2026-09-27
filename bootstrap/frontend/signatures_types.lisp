;; Layout declarations shared by compiler code and hosted driver storage.
(include "layout_types.lisp")

(defcstruct native_parameter
  (name usize)
  (type_ast usize)
  (size usize)
  (kind u32))

(defcstruct native_signature
  (name usize)
  (first_parameter usize)
  (arity usize)
  (result_type usize)
  (result_size usize)
  (result_kind u32)
  (body usize)
  (exported u8)
  (imported u8))

(defcstruct native_signature_context
  (layouts (ptr native_layout_context))
  (signatures (ptr native_signature))
  (signature_count usize)
  (signature_capacity usize)
  (parameters (ptr native_parameter))
  (parameter_count usize)
  (parameter_capacity usize)
  (error u32))
