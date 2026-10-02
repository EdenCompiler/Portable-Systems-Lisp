(include "symbols.lisp")
(include "identity_syntax.lisp")

;; AST navigation and simple symbol spelling for the native scalar subset.

(defun ast_first (parser reference)
  (declare (type (ptr psl_parser) parser)
           (type usize reference)
           (returns usize))
  (if (= reference 0)
      0
      (deref (field-pointer (parser_node parser reference) 'first))))

(defun ast_next (parser reference)
  (declare (type (ptr psl_parser) parser)
           (type usize reference)
           (returns usize))
  (if (= reference 0)
      0
      (deref (field-pointer (parser_node parser reference) 'next))))

(defun ast_nth (parser reference index)
  (declare (type (ptr psl_parser) parser)
           (type usize reference index)
           (returns usize))
  (if (= index 0)
      reference
      (ast_nth parser (ast_next parser reference) (wrap- index 1))))

(defun ascii_matches (source start bits remaining)
  (declare (type (ptr u8) source) (type usize start remaining)
           (type u64 bits) (returns c-int))
  (source_bytes_match source start bits remaining))

(defun ast_word_p (parser source reference bits length)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize reference length) (type u64 bits) (returns c-int))
  (if (= reference 0) 0
      (let ((node (parser_node parser reference)))
        (if (= (deref (field-pointer node 'kind)) 8)
            (ast_builtin_word_p parser source reference bits 0 length)
            0))))

(defun ast_list_p (parser reference)
  (declare (type (ptr psl_parser) parser)
           (type usize reference)
           (returns c-int))
  (if (= reference 0)
      0
      (if (= (deref (field-pointer (parser_node parser reference)
                                   'kind)) 1)
          1
          0)))

(defun ast_long_word_p (parser source reference first last length)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize reference length) (type u64 first last) (returns c-int))
  (if (= reference 0) 0
      (let ((node (parser_node parser reference)))
        (if (= (deref (field-pointer node 'kind)) 8)
            (ast_builtin_word_p parser source reference first last length)
            0))))

(defun ast_simple_name_p (parser source reference)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize reference)
           (returns c-int))
  (if (= reference 0)
      0
      (let ((node (parser_node parser reference)))
        (if (= (deref (field-pointer node 'kind)) 8)
            (simple_source_name_p
             source (deref (field-pointer node 'start))
             (deref (field-pointer node 'length)))
            0))))

(defun ast_variable_name_p (parser source reference)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize reference) (returns c-int))
  (if (= (ast_simple_name_p parser source reference) 0)
      0
      (if (= (ast_word_p parser source reference #x74 1) 1)
          0
          (if (= (ast_word_p parser source reference #x6c696e 3) 1) 0 1))))

(defun ast_raw_names_equal_p (parser source left right)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize left right) (returns c-int))
  (let ((a (parser_node parser left)) (b (parser_node parser right)))
    (let ((length (deref (field-pointer a 'length))))
      (if (= length (deref (field-pointer b 'length)))
          (source_same_name_p
           (pointer+ source (wrap-cast isize (deref (field-pointer a 'start))))
           (pointer+ source (wrap-cast isize (deref (field-pointer b 'start))))
           length)
          0))))

(defun ast_same_name_p (parser source left right)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize left right) (returns c-int))
  (if (= left 0) 0
      (if (= right 0) 0
          (let ((identity (ast_symbol_identity parser left)))
            (if (= identity 0) (ast_raw_names_equal_p parser source left right)
                (if (= identity (ast_symbol_identity parser right)) 1 0))))))

(defun lowercase_letter_p (byte)
  (declare (type u8 byte) (returns c-int))
  (if (< 96 byte)
      (if (< byte 123) 1 0)
      0))

(defun uppercase_letter_p (byte)
  (declare (type u8 byte) (returns c-int))
  (if (< 64 byte)
      (if (< byte 91) 1 0)
      0))

(defun c_name_byte_p (byte first)
  (declare (type u8 byte first) (returns c-int))
  (if (= (lowercase_letter_p byte) 1)
      1
      (if (= byte 95)
          1
          (if (= first 1)
              0
              (if (< 47 byte)
                  (if (< byte 58) 1 0)
                  0)))))

(defun simple_export_name_from (source start length index)
  (declare (type (ptr u8) source)
           (type usize start length index)
           (returns c-int))
  (if (= index length)
      1
      (let ((byte (deref (pointer+ source
                                  (wrap-cast isize (wrap+ start index))))))
        (if (= (c_name_byte_p (source_fold_byte byte) (if (= index 0) 1 0)) 1)
            (simple_export_name_from source start length (wrap+ index 1))
            0))))

(defun simple_export_name_p (source start length)
  (declare (type (ptr u8) source)
           (type usize start length)
           (returns c-int))
  (if (= length 0)
      0
      (if (< 255 length)
          0
          (simple_export_name_from source start length 0))))

(defun c_import_name_byte_p (byte first)
  (declare (type u8 byte first) (returns c-int))
  (if (= (uppercase_letter_p byte) 1) 1
      (c_name_byte_p (source_fold_byte byte) first)))

(defun simple_import_name_from (source start length index)
  (declare (type (ptr u8) source)
           (type usize start length index)
           (returns c-int))
  (if (= index length) 1
      (let ((byte (deref (pointer+ source
                                  (wrap-cast isize (wrap+ start index))))))
        (if (= (c_import_name_byte_p byte (if (= index 0) 1 0)) 1)
            (simple_import_name_from source start length (wrap+ index 1))
            0))))

(defun simple_import_name_p (source start length)
  (declare (type (ptr u8) source)
           (type usize start length)
           (returns c-int))
  (if (= length 0) 0
      (if (< 255 length) 0
          (simple_import_name_from source start length 0))))

(defun source_name_byte_p (byte first)
  (declare (type u8 byte first) (returns c-int))
  (source_identifier_byte_p byte first))

(defun simple_source_name_from (source start length index)
  (declare (type (ptr u8) source)
           (type usize start length index)
           (returns c-int))
  (source_identifier_from source start length index))

(defun simple_source_name_p (source start length)
  (declare (type (ptr u8) source)
           (type usize start length)
           (returns c-int))
  (source_simple_identifier_p source start length))
