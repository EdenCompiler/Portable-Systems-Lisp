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
  (declare (type (ptr u8) source)
           (type usize start remaining)
           (type u64 bits)
           (returns c-int))
  (if (= remaining 0)
      1
      (if (= (deref (pointer+ source (wrap-cast isize start)))
             (wrap-cast u8 bits))
          (ascii_matches source (wrap+ start 1) (shr64 bits 8)
                         (wrap- remaining 1))
          0)))

(defun ast_word_p (parser source reference bits length)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize reference length)
           (type u64 bits)
           (returns c-int))
  (if (= reference 0)
      0
      (let ((node (parser_node parser reference)))
        (if (= (deref (field-pointer node 'kind)) 8)
            (if (= (deref (field-pointer node 'length)) length)
                (ascii_matches source
                               (deref (field-pointer node 'start))
                               bits length)
                0)
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
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize reference length)
           (type u64 first last) (returns c-int))
  (if (= reference 0)
      0
      (let ((node (parser_node parser reference)))
        (if (= (deref (field-pointer node 'kind)) 8)
            (if (= (deref (field-pointer node 'length)) length)
                (let ((start (deref (field-pointer node 'start))))
                  (if (= (ascii_matches source start first 8) 1)
                      (ascii_matches source (wrap+ start 8) last
                                     (wrap- length 8))
                      0))
                0)
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

(defun ast_same_name_p (parser source left right)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize left right)
           (returns c-int))
  (if (= left 0)
      0
      (if (= right 0)
          0
          (let ((left_node (parser_node parser left))
                (right_node (parser_node parser right)))
            (let ((length (deref (field-pointer left_node 'length))))
              (if (= length (deref (field-pointer right_node 'length)))
                  (same_name_bytes_p
                   (pointer+ source
                             (wrap-cast isize
                                        (deref (field-pointer left_node
                                                              'start))))
                   (pointer+ source
                             (wrap-cast isize
                                        (deref (field-pointer right_node
                                                              'start))))
                   length)
                  0))))))


(defun lowercase_letter_p (byte)
  (declare (type u8 byte) (returns c-int))
  (if (< 96 byte)
      (if (< byte 123) 1 0)
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
        (if (= (c_name_byte_p byte (if (= index 0) 1 0)) 1)
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

(defun source_name_byte_p (byte first)
  (declare (type u8 byte first) (returns c-int))
  (if (= byte 45)
      (if (= first 1) 0 1)
      (c_name_byte_p byte first)))

(defun simple_source_name_from (source start length index)
  (declare (type (ptr u8) source)
           (type usize start length index)
           (returns c-int))
  (if (= index length)
      1
      (let ((byte (deref (pointer+ source
                                  (wrap-cast isize (wrap+ start index))))))
        (if (= (source_name_byte_p byte (if (= index 0) 1 0)) 1)
            (simple_source_name_from source start length (wrap+ index 1))
            0))))

(defun simple_source_name_p (source start length)
  (declare (type (ptr u8) source)
           (type usize start length)
           (returns c-int))
  (if (= length 0)
      0
      (if (< 255 length)
          0
          (simple_source_name_from source start length 0))))
