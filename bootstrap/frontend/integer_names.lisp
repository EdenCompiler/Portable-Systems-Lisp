(include "../target.lisp")
(include "../ir/integer_types.lisp")

;; Source names resolve to target-independent machine type codes. The target
;; contract supplies the ABI-dependent C long width.

(defun layout_type_word_p (context reference first last length)
  (declare (type (ptr native_layout_context) context)
           (type usize reference length) (type u64 first last) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (layout_atom_p parser reference) 0) 0
        (let ((node (parser_node parser reference)))
          (source_builtin_word_p (deref (field-pointer context 'source))
             (deref (field-pointer node 'start))
             (deref (field-pointer node 'length)) first last length)))))

(defun layout_integer_code (context type)
  (declare (type (ptr native_layout_context) context)
           (type usize type) (returns u32))
  (cond
    ((= (layout_type_word_p context type #x343675 0 3) 1) 1) ; u64
    ((= (layout_type_word_p context type #x657a697375 0 5) 1) 2) ; usize
    ((= (layout_type_word_p context type #x3875 0 2) 1) 3) ; u8
    ((= (layout_type_word_p context type #x363175 0 3) 1) 4) ; u16
    ((= (layout_type_word_p context type #x323375 0 3) 1) 5) ; u32
    ((= (layout_type_word_p context type #x3873 0 2) 1) 6) ; s8
    ((= (layout_type_word_p context type #x363173 0 3) 1) 7) ; s16
    ((= (layout_type_word_p context type #x323373 0 3) 1) 8) ; s32
    ((= (layout_type_word_p context type #x343673 0 3) 1) 9) ; s64
    ((= (layout_type_word_p context type #x657a697369 0 5) 1) 10) ; isize
    ((= (layout_type_word_p context type #x726168632d63 0 6) 1) 6) ; c-char
    ((= (layout_type_word_p context type #x72616863752d63 0 7) 1) 3) ; c-uchar
    ((= (layout_type_word_p context type #x74726f68732d63 0 7) 1) 7) ; c-short
    ((= (layout_type_word_p context type #x74726f6873752d63 0 8) 1) 4) ; c-ushort
    ((= (layout_type_word_p context type #x746e692d63 0 5) 1) 8) ; c-int
    ((= (layout_type_word_p context type #x746e69752d63 0 6) 1) 5) ; c-uint
    ((= (layout_type_word_p context type #x6c2d676e6f6c2d63 #x676e6f 11) 1) 9) ; c-long-long
    ((= (layout_type_word_p context type #x2d676e6f6c752d63 #x676e6f6c 12) 1) 1) ; c-ulong-long
    ((= (layout_type_word_p context type #x742d657a69732d63 0 8) 1) 2) ; c-size-t
    ((= (layout_type_word_p context type #x6669647274702d63 #x742d66 11) 1) 10) ; c-ptrdiff-t
    ((= (layout_type_word_p context type #x676e6f6c2d63 0 6) 1)
     (if (= (native_target_c_long_bits (deref (field-pointer context 'target))) 32)
         8 (wrap-cast u32 9))) ; c-long
    ((= (layout_type_word_p context type #x676e6f6c752d63 0 7) 1)
     (if (= (native_target_c_long_bits (deref (field-pointer context 'target))) 32)
         5 (wrap-cast u32 1))) ; c-ulong
    (t 0)))
