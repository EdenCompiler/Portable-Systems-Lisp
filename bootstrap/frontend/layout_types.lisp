;; Layout declarations shared by compiler code and hosted driver storage.
(include "parser_types.lisp")

(defcstruct native_type_shape
  (size usize)
  (alignment usize)
  (kind u32)
  (pointee usize))

(defcstruct native_layout_field
  (name usize)
  (type_ast usize)
  (offset usize)
  (size usize)
  (alignment usize))

(defcstruct native_layout
  (name usize)
  (first usize)
  (count usize)
  (size usize)
  (alignment usize))

(defcstruct native_layout_context
  (parser (ptr psl_parser))
  (source (ptr u8))
  (layouts (ptr native_layout))
  (layout_count usize)
  (layout_capacity usize)
  (fields (ptr native_layout_field))
  (field_count usize)
  (field_capacity usize)
  (scratch (ptr native_type_shape))
  (error u32))
