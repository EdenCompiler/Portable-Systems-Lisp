(include "data_types.lisp")

(defun native_data_import_at (context index)
  (declare (type (ptr native_compile_context) context) (type usize index)
           (returns (ptr native_data_import)))
  (pointer+ (deref (field-pointer context 'data_imports))
            (wrap-cast isize index)))

(defun native_import_data_form_p (context root)
  (declare (type (ptr native_compile_context) context)
           (type usize root) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (if (= (ast_list_p parser root) 0) 0
        (ast_long_word_p parser source (ast_first parser root)
                         #x6f706d693a696666 #x617461642d7472 15))))

(defun native_export_data_form_p (context root)
  (declare (type (ptr native_compile_context) context)
           (type usize root) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (if (= (ast_list_p parser root) 0) 0
        (ast_long_word_p parser source (ast_first parser root)
                         #x6f7078653a696666 #x617461642d7472 15))))

(defun native_data_name_matches_p (context name index imported)
  (declare (type (ptr native_compile_context) context)
           (type usize name index) (type u8 imported) (returns c-int))
  (let ((node (parser_node (deref (field-pointer context 'parser)) name))
        (entry (native_data_import_at context index))
        (source (deref (field-pointer context 'source))))
    (if (= (deref (field-pointer entry 'global)) 0) 0
        (if (= (deref (field-pointer node 'length))
           (deref (field-pointer entry 'name_length)))
            (if (= imported 1)
                (same_name_bytes_p
                 (pointer+ source
                           (wrap-cast isize (deref (field-pointer node 'start))))
                 (deref (field-pointer entry 'name))
                 (deref (field-pointer entry 'name_length)))
                (source_foreign_name_p
                 (pointer+ source
                           (wrap-cast isize (deref (field-pointer node 'start))))
                 (deref (field-pointer entry 'name))
                 (deref (field-pointer entry 'name_length))))
            0))))

(defun native_data_name_used_from (context name imported index)
  (declare (type (ptr native_compile_context) context)
           (type usize name index) (type u8 imported) (returns c-int))
  (if (= index (deref (field-pointer context 'data_count))) 0
      (if (= (native_data_name_matches_p context name index imported) 1) 1
          (native_data_name_used_from context name imported (wrap+ index 1)))))

(defun native_latest_signature_data_name_free_p (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (let ((count (deref (field-pointer signatures 'signature_count))))
      (if (= count 0) 0
          (let ((signature (native_signature_at signatures (wrap- count 1))))
            (if (= (native_data_name_used_from
                    context (deref (field-pointer signature 'name))
                    (deref (field-pointer signature 'imported)) 0) 0)
                1 0))))))

(defun native_initialize_data_entry (context entry name type shape initial defined)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_data_import) entry)
           (type (ptr native_type_shape) shape)
           (type usize name type) (type u64 initial) (type u8 defined)
           (returns c-int))
  (let ((node (parser_node (deref (field-pointer context 'parser)) name)))
    (store (field-pointer entry 'name)
           (pointer+ (deref (field-pointer context 'source))
                     (wrap-cast isize (deref (field-pointer node 'start)))))
    (store (field-pointer entry 'name_length)
           (deref (field-pointer node 'length)))
    (store (field-pointer entry 'type_ast) type)
    (store (field-pointer entry 'size) (deref (field-pointer shape 'size)))
    (store (field-pointer entry 'alignment)
           (deref (field-pointer shape 'alignment)))
    (store (field-pointer entry 'bytes) (ptr-from-address (ptr u8) 0))
    (store (field-pointer entry 'initial) initial)
    (store (field-pointer entry 'defined) defined)
    (store (field-pointer entry 'global) 1)
    (store (field-pointer entry 'referenced) 0)
    1))

(defun native_data_declaration_free_p (context signatures name)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature_context) signatures)
           (type usize name) (returns c-int))
  (if (= (signature_foreign_name_used_p signatures name 0) 1) 0
      (if (= (native_data_name_used_from context name 1 0) 1) 0 1)))

(defun native_parse_data_type (context type shape)
  (declare (type (ptr native_compile_context) context)
           (type usize type) (type (ptr native_type_shape) shape)
           (returns u32))
  (if (= (native_resolve_type (source_layouts context) type shape) 0) 0
      (let ((code (scalar_type_code
                   (deref (field-pointer context 'signatures)) type)))
        (if (= (source_valid_code_p code) 1) code 0))))

(defun native_commit_data_entry (context entry name type shape initial defined)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_data_import) entry)
           (type (ptr native_type_shape) shape)
           (type usize name type) (type u64 initial) (type u8 defined)
           (returns c-int))
  (native_initialize_data_entry context entry name type shape initial defined)
  (store (field-pointer context 'data_count)
         (wrap+ (deref (field-pointer context 'data_count)) 1))
  1)

(defun native_parse_import_data (context root)
  (declare (type (ptr native_compile_context) context)
           (type usize root) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (signatures (deref (field-pointer context 'signatures))))
    (let ((raw_name (ast_next parser (ast_first parser root))))
      (let ((name (import_name_atom signatures raw_name))
            (type (ast_next parser raw_name))
            (count (deref (field-pointer context 'data_count)))
            (shape (deref (field-pointer (source_layouts context) 'scratch))))
        (cond
          ((= name 0) 0)
          ((= (call_shape_from_p parser raw_name 2) 0) 0)
          ((= (native_data_declaration_free_p context signatures name) 0) 0)
          ((= count (deref (field-pointer context 'data_capacity))) 0)
          ((= (native_parse_data_type context type shape) 0) 0)
          (t (native_commit_data_entry
              context (native_data_import_at context count)
              name type shape 0 0)))))))

(defun native_parse_export_initializer (context code initializer)
  (declare (type (ptr native_compile_context) context)
           (type usize initializer) (type u32 code) (returns c-int))
  (let ((integer (deref (field-pointer context 'integer))))
    (if (= (source_float_code_p code) 1)
        (if (= (scalar_float_atom_p context initializer) 1)
            (if (= (wrap-cast u32 (deref (field-pointer integer 'radix))) code) 1 0) 0)
    (if (= (scalar_integer_atom_p
            (deref (field-pointer context 'parser))
            (deref (field-pointer context 'source)) initializer integer) 0)
        0
        (if (= code 11)
            (if (= (deref (field-pointer integer 'magnitude)) 0) 1 0)
            (scalar_literal_valid_p code integer))))))

(defun native_export_initializer_bits (context)
  (declare (type (ptr native_compile_context) context)
           (returns u64))
  (let ((integer (deref (field-pointer context 'integer))))
    (if (= (source_float_code_p (wrap-cast u32 (deref (field-pointer integer 'radix)))) 1)
        (deref (field-pointer integer 'magnitude))
        (scalar_literal_bits integer))))

(defun native_parse_export_data (context root)
  (declare (type (ptr native_compile_context) context)
           (type usize root) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (signatures (deref (field-pointer context 'signatures))))
    (let ((raw_name (ast_next parser (ast_first parser root))))
      (let ((name (import_name_atom signatures raw_name))
            (type (ast_next parser raw_name))
            (count (deref (field-pointer context 'data_count)))
            (shape (deref (field-pointer (source_layouts context) 'scratch))))
        (cond
          ((= name 0) 0)
          ((= (call_shape_from_p parser raw_name 3) 0) 0)
          ((= (native_data_declaration_free_p context signatures name) 0) 0)
          ((= count (deref (field-pointer context 'data_capacity))) 0)
          (t
           (let ((initializer (ast_next parser type)))
             (let ((code (native_parse_data_type context type shape)))
               (if (= code 0) 0
                   (if (= (native_parse_export_initializer
                           context code initializer) 0) 0
                       (let ((bits (native_export_initializer_bits context)))
                         (native_commit_data_entry
                          context (native_data_import_at context count)
                          name type shape bits 1))))))))))))

(defun native_data_designator (context reference)
  (declare (type (ptr native_compile_context) context)
           (type usize reference) (returns usize))
  (if (= reference 0) 0
      (let ((node (parser_node (deref (field-pointer context 'parser)) reference)))
        (if (= (deref (field-pointer node 'kind)) 8) reference
            (import_name_atom (deref (field-pointer context 'signatures)) reference)))))

(defun native_find_data_import_from (context name index)
  (declare (type (ptr native_compile_context) context)
           (type usize name index) (returns usize))
  (if (= index (deref (field-pointer context 'data_count))) 0
      (if (= (native_data_name_matches_p context name index 1) 1)
          (wrap+ index 1)
          (native_find_data_import_from context name (wrap+ index 1)))))

(defun analyze_data_address (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((raw_name (ast_next parser (ast_first parser body))))
      (if (= (call_shape_from_p parser raw_name 1) 0) 0
          (let ((name (native_data_designator context raw_name)))
            (if (= name 0) 0
                (let ((index (native_find_data_import_from context name 0)))
                  (if (= index 0) 0
                      (let ((entry (native_data_import_at context (wrap- index 1))))
                        (hir_with_pointee
                         (deref (field-pointer context 'hir))
                         (hir_new_scalar (deref (field-pointer context 'hir))
                                         34 0 0 0 index body 11)
                         (deref (field-pointer entry 'type_ast))))))))))))
