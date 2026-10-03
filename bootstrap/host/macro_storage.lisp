;; Build-host macro definitions and argument bindings have separate ownership.
(defun native_allocate_macros (storage)
  (declare (type (ptr native_storage) storage) (returns c-int))
  (store (field-pointer storage 'macro_definitions)
         (ptr-cast (ptr native_macro_definition)
                   (ffi:call calloc 256 (sizeof 'native_macro_definition))))
  (store (field-pointer storage 'macro_bindings)
         (ptr-cast (ptr native_macro_binding)
                   (ffi:call calloc 128 (sizeof 'native_macro_binding))))
  (if (= (ptr-address (deref (field-pointer storage 'macro_definitions))) 0) 0
      (if (= (ptr-address (deref (field-pointer storage 'macro_bindings))) 0) 0 1)))

(defun native_release_macros (storage)
  (declare (type (ptr native_storage) storage) (returns c-int))
  (ffi:call free (ptr-cast (ptr void) (deref (field-pointer storage 'macro_definitions))))
  (store (field-pointer storage 'macro_definitions) (ptr-from-address (ptr native_macro_definition) 0))
  (ffi:call free (ptr-cast (ptr void) (deref (field-pointer storage 'macro_bindings))))
  (store (field-pointer storage 'macro_bindings) (ptr-from-address (ptr native_macro_binding) 0))
  1)
