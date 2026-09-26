(include "parser.lisp")

;; Native structure metadata uses parser references, not host Lisp objects.
;; Only earlier structures may appear in a type, matching Stage 0's layout
;; registration order. Pointer layout is independent of its pointee's size.
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

(defun native_layout_at (context index)
  (declare (type (ptr native_layout_context) context)
           (type usize index)
           (returns (ptr native_layout)))
  (pointer+ (deref (field-pointer context 'layouts))
            (wrap-cast isize index)))

(defun native_field_at (context index)
  (declare (type (ptr native_layout_context) context)
           (type usize index)
           (returns (ptr native_layout_field)))
  (pointer+ (deref (field-pointer context 'fields))
            (wrap-cast isize index)))

(defun layout_atom_p (parser reference)
  (declare (type (ptr psl_parser) parser)
           (type usize reference)
           (returns c-int))
  (if (= reference 0)
      0
      (if (= (deref (field-pointer (parser_node parser reference) 'kind)) 8)
          1 0)))

(defun layout_bytes_match (source start bits count)
  (declare (type (ptr u8) source)
           (type usize start count)
           (type u64 bits)
           (returns c-int))
  (if (= count 0)
      1
      (if (= (deref (pointer+ source (wrap-cast isize start)))
             (wrap-cast u8 bits))
          (layout_bytes_match source (wrap+ start 1) (shr64 bits 8)
                              (wrap- count 1))
          0)))

(defun layout_word_p (context reference bits length)
  (declare (type (ptr native_layout_context) context)
           (type usize reference length)
           (type u64 bits)
           (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (layout_atom_p parser reference) 0)
        0
        (let ((node (parser_node parser reference)))
          (if (= (deref (field-pointer node 'length)) length)
              (layout_bytes_match
               (deref (field-pointer context 'source))
               (deref (field-pointer node 'start)) bits length)
              0)))))

(defun native_layout_form_p (context root)
  (declare (type (ptr native_layout_context) context)
           (type usize root)
           (returns c-int)
           (c-export :c))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= root 0)
        0
        (if (= (deref (field-pointer (parser_node parser root) 'kind)) 1)
            (let ((head (deref (field-pointer (parser_node parser root)
                                              'first))))
              (if (= (layout_atom_p parser head) 0)
                  0
                  (let ((node (parser_node parser head)))
                    (if (= (deref (field-pointer node 'length)) 10)
                        (let ((start (deref (field-pointer node 'start)))
                              (source (deref (field-pointer context 'source))))
                          (if (= (layout_bytes_match source start
                                                     #x7572747363666564 8) 1)
                              (layout_bytes_match source (wrap+ start 8)
                                                  #x7463 2)
                              0))
                        0))))
            0))))

(defun layout_names_equal_p (context left right)
  (declare (type (ptr native_layout_context) context)
           (type usize left right)
           (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (layout_atom_p parser left) 0)
        0
        (if (= (layout_atom_p parser right) 0)
            0
            (let ((a (parser_node parser left))
                  (b (parser_node parser right)))
              (let ((length (deref (field-pointer a 'length))))
                (if (= length (deref (field-pointer b 'length)))
                    (layout_same_bytes_p
                     (deref (field-pointer context 'source))
                     (deref (field-pointer a 'start))
                     (deref (field-pointer b 'start)) length)
                    0)))))))

(defun layout_same_bytes_p (source left right count)
  (declare (type (ptr u8) source)
           (type usize left right count)
           (returns c-int))
  (if (= count 0)
      1
      (if (= (deref (pointer+ source (wrap-cast isize left)))
             (deref (pointer+ source (wrap-cast isize right))))
          (layout_same_bytes_p source (wrap+ left 1) (wrap+ right 1)
                               (wrap- count 1))
          0)))

(defun native_find_layout (context name)
  (declare (type (ptr native_layout_context) context)
           (type usize name)
           (returns usize)
           (c-export :c))
  (native_find_layout_from context name 0))

(defun native_find_layout_from (context name index)
  (declare (type (ptr native_layout_context) context)
           (type usize name index)
           (returns usize))
  (if (= index (deref (field-pointer context 'layout_count)))
      0
      (if (= (layout_names_equal_p
              context name
              (deref (field-pointer (native_layout_at context index) 'name))) 1)
          (wrap+ index 1)
          (native_find_layout_from context name (wrap+ index 1)))))

(defun layout_set_shape (output size alignment kind pointee)
  (declare (type (ptr native_type_shape) output)
           (type usize size alignment pointee)
           (type u32 kind)
           (returns c-int))
  (store (field-pointer output 'size) size)
  (store (field-pointer output 'alignment) alignment)
  (store (field-pointer output 'kind) kind)
  (store (field-pointer output 'pointee) pointee)
  1)

(defun layout_primitive_size (context type)
  (declare (type (ptr native_layout_context) context)
           (type usize type)
           (returns usize))
  (cond
    ((= (layout_word_p context type #x3875 2) 1) 1) ; u8
    ((= (layout_word_p context type #x3873 2) 1) 1) ; s8
    ((= (layout_word_p context type #x363175 3) 1) 2) ; u16
    ((= (layout_word_p context type #x363173 3) 1) 2) ; s16
    ((= (layout_word_p context type #x323375 3) 1) 4) ; u32
    ((= (layout_word_p context type #x323373 3) 1) 4) ; s32
    ((= (layout_word_p context type #x746e692d63 5) 1) 4) ; c-int
    ((= (layout_word_p context type #x323366 3) 1) 4) ; f32
    ((= (layout_word_p context type #x343675 3) 1) 8) ; u64
    ((= (layout_word_p context type #x343673 3) 1) 8) ; s64
    ((= (layout_word_p context type #x657a697375 5) 1) 8) ; usize
    ((= (layout_word_p context type #x657a697369 5) 1) 8) ; isize
    ((= (layout_word_p context type #x343666 3) 1) 8) ; f64
    (t 0)))

(defun native_resolve_type (context type output)
  (declare (type (ptr native_layout_context) context)
           (type usize type)
           (type (ptr native_type_shape) output)
           (returns c-int)
           (c-export :c))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (layout_atom_p parser type) 1)
        (let ((size (layout_primitive_size context type)))
          (if (< 0 size)
              (layout_set_shape output size size 1 0)
              (let ((index (native_find_layout context type)))
                (if (= index 0)
                    0
                    (let ((layout (native_layout_at context
                                                    (wrap- index 1))))
                      (layout_set_shape
                       output (deref (field-pointer layout 'size))
                       (deref (field-pointer layout 'alignment)) 3
                       index))))))
        (native_resolve_pointer_type context type output))))

(defun native_resolve_pointer_type (context type output)
  (declare (type (ptr native_layout_context) context)
           (type usize type)
           (type (ptr native_type_shape) output)
           (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= type 0)
        0
        (let ((node (parser_node parser type)))
          (if (= (deref (field-pointer node 'kind)) 1)
              (let ((head (deref (field-pointer node 'first))))
                (let ((pointee (if (= head 0) (wrap-cast usize 0)
                                   (deref (field-pointer
                                           (parser_node parser head) 'next)))))
                  (if (= (layout_word_p context head #x727470 3) 1)
                      (if (< 0 pointee)
                          (if (= (deref (field-pointer
                                  (parser_node parser pointee) 'next)) 0)
                              (if (= (native_resolve_type
                                      context pointee output) 1)
                                  (layout_set_shape output 8 8 2 pointee)
                                  0)
                              0)
                          0)
                      0)))
              0)))))

(defun layout_round_up (value alignment)
  (declare (type usize value alignment) (returns usize))
  (bits-and (wrap+ value (wrap- alignment 1))
            (wrap- 0 alignment)))

(defun layout_field_already_p (context first count name)
  (declare (type (ptr native_layout_context) context)
           (type usize first count name)
           (returns c-int))
  (if (= count 0)
      0
      (if (= (layout_names_equal_p
              context name
              (deref (field-pointer (native_field_at context first) 'name))) 1)
          1
          (layout_field_already_p context (wrap+ first 1)
                                  (wrap- count 1) name))))

(defun layout_field_name (context field)
  (declare (type (ptr native_layout_context) context)
           (type usize field)
           (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= field 0)
        0
        (if (= (deref (field-pointer (parser_node parser field) 'kind)) 1)
            (let ((name (deref (field-pointer (parser_node parser field)
                                             'first))))
              (if (= (layout_atom_p parser name) 0)
                  0
                  (let ((type (deref (field-pointer (parser_node parser name)
                                                    'next))))
                    (if (= type 0)
                        0
                        (if (= (deref (field-pointer
                                (parser_node parser type) 'next)) 0)
                            name
                            0)))))
            0))))

(defun layout_add_named_field (context name layout shape)
  (declare (type (ptr native_layout_context) context)
           (type usize name)
           (type (ptr native_layout) layout)
           (type (ptr native_type_shape) shape)
           (returns c-int))
  (if (= (layout_field_already_p
          context (deref (field-pointer layout 'first))
          (deref (field-pointer layout 'count)) name) 1)
      0
      (let ((type (deref (field-pointer
                          (parser_node (deref (field-pointer context 'parser))
                                       name)
                          'next))))
        (if (= (native_resolve_type context type shape) 1)
            (layout_commit_field context layout name type shape)
            0))))

(defun layout_add_field (context field layout shape)
  (declare (type (ptr native_layout_context) context)
           (type usize field)
           (type (ptr native_layout) layout)
           (type (ptr native_type_shape) shape)
           (returns c-int))
  (if (= (deref (field-pointer context 'field_count))
         (deref (field-pointer context 'field_capacity)))
      0
      (let ((name (layout_field_name context field)))
        (if (= name 0)
            0
            (layout_add_named_field context name layout shape)))))

(defun layout_commit_field (context layout name type shape)
  (declare (type (ptr native_layout_context) context)
           (type (ptr native_layout) layout)
           (type usize name type)
           (type (ptr native_type_shape) shape)
           (returns c-int))
  (let ((size (deref (field-pointer shape 'size)))
        (alignment (deref (field-pointer shape 'alignment)))
        (offset (deref (field-pointer layout 'size))))
    (let ((aligned (layout_round_up offset alignment)))
      (if (< aligned offset)
          0
          (if (< (wrap- 0 size) aligned)
              0
              (let ((entry (native_field_at
                            context (deref (field-pointer context
                                                        'field_count)))))
                (store (field-pointer entry 'name) name)
                (store (field-pointer entry 'type_ast) type)
                (store (field-pointer entry 'offset) aligned)
                (store (field-pointer entry 'size) size)
                (store (field-pointer entry 'alignment) alignment)
                (store (field-pointer context 'field_count)
                       (wrap+ (deref (field-pointer context 'field_count)) 1))
                (store (field-pointer layout 'count)
                       (wrap+ (deref (field-pointer layout 'count)) 1))
                (store (field-pointer layout 'size) (wrap+ aligned size))
                (if (< (deref (field-pointer layout 'alignment)) alignment)
                    (store (field-pointer layout 'alignment) alignment)
                    (wrap-cast usize 0))
                1))))))

(defun layout_add_fields (context layout field shape)
  (declare (type (ptr native_layout_context) context)
           (type (ptr native_layout) layout)
           (type usize field)
           (type (ptr native_type_shape) shape)
           (returns c-int))
  (if (= field 0)
      1
      (if (= (layout_add_field context field layout shape) 1)
          (layout_add_fields
           context layout
           (deref (field-pointer
                   (parser_node (deref (field-pointer context 'parser)) field)
                   'next)) shape)
          0)))

(defun native_register_layout (context root)
  (declare (type (ptr native_layout_context) context)
           (type usize root)
           (returns c-int)
           (c-export :c))
  (if (= (native_layout_form_p context root) 0)
      0
      (let ((parser (deref (field-pointer context 'parser))))
        (let ((head (deref (field-pointer (parser_node parser root) 'first))))
          (let ((name (deref (field-pointer (parser_node parser head)
                                          'next))))
            (if (= (layout_atom_p parser name) 0)
                0
                (if (< 0 (native_find_layout context name))
                    0
                    (if (= (deref (field-pointer context 'layout_count))
                           (deref (field-pointer context 'layout_capacity)))
                        0
                        (native_register_layout_body
                         context name
                         (deref (field-pointer (parser_node parser name)
                                               'next)))))))))))

(defun native_register_layout_body (context name first_field)
  (declare (type (ptr native_layout_context) context)
           (type usize name first_field)
           (returns c-int))
  (if (= first_field 0)
      0
      (let ((layout (native_layout_at
                     context (deref (field-pointer context 'layout_count)))))
        (store (field-pointer layout 'name) name)
        (store (field-pointer layout 'first)
               (deref (field-pointer context 'field_count)))
        (store (field-pointer layout 'count) 0)
        (store (field-pointer layout 'size) 0)
        (store (field-pointer layout 'alignment) 1)
        (if (= (layout_add_fields context layout first_field
                                 (deref (field-pointer context 'scratch))) 0)
            (progn (store (field-pointer context 'error) 1) 0)
            (let ((size (deref (field-pointer layout 'size)))
                  (alignment (deref (field-pointer layout 'alignment))))
              (let ((rounded (layout_round_up size alignment)))
                (if (< rounded size)
                    (progn (store (field-pointer context 'error) 1) 0)
                    (progn
                      (store (field-pointer layout 'size) rounded)
                      (store (field-pointer context 'layout_count)
                             (wrap+ (deref (field-pointer context
                                                         'layout_count)) 1))
                      1))))))))
