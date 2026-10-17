(include "../compile_scalar_types.lisp")
(include "environment/resolve.lisp")
(include "package_forms.lisp")

;; The source loader shares reader and package semantics with compilation,
;; without allocating HIR, SSA, LIR or output arenas. Its context is opaque to
;; the separately compiled hosted source unit.
(defcstruct native_source_reader_state
  (context native_compile_context)
  (integer psl_parsed_integer))

(defun native_source_reader_state_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'native_source_reader_state))

(defun native_source_reader_form (memory parser source root scratch)
  (declare (type (ptr void) memory) (type (ptr psl_parser) parser)
           (type (ptr u8) source scratch) (type usize root)
           (returns u32) (c-export :c))
  (let ((state (ptr-cast (ptr native_source_reader_state) memory)))
    (let ((context (field-pointer state 'context))
          (reader (deref (field-pointer parser 'environment))))
      (if (= (ptr-address reader) 0) 0
          (progn
            (store (field-pointer context 'parser) parser)
            (store (field-pointer context 'source) source)
            (store (field-pointer context 'integer) (field-pointer state 'integer))
            (store (field-pointer context 'data_bytes) scratch)
            (store (field-pointer context 'data_byte_count) 0)
            (store (field-pointer context 'data_byte_capacity) 4096)
            (if (= (native_resolve_source_identities context reader) 0) 0
                (if (< 0 (native_source_package_kind context root))
                    (if (= (native_apply_package_form context root
                             (field-pointer context 'package_state)) 1) 1 0)
                    (native_source_form_kind parser source root))))))))
