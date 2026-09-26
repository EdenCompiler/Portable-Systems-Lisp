(include "parser.lisp")

;; Source-unit loading uses this parser interface. The host supplies file I/O
;; and canonical paths; PSL recognizes include forms and decodes their strings.
(defun source_include_head_p (parser source root)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize root) (returns c-int))
  (let ((form (parser_node parser root)))
    (if (= (deref (field-pointer form 'kind)) 1)
        (let ((head (deref (field-pointer form 'first))))
          (if (= head 0) 0
              (let ((node (parser_node parser head)))
                (if (= (deref (field-pointer node 'kind)) 8)
                    (if (= (deref (field-pointer node 'length)) 7)
                        (source_include_name_p source (deref (field-pointer node 'start)) 0)
                        0)
                    0))))
        0)))

(defun source_include_name_p (source start index)
  (declare (type (ptr u8) source) (type usize start index) (returns c-int))
  (if (= index 7) 1
      (if (= (deref (pointer+ source (wrap-cast isize (wrap+ start index))))
             (wrap-cast u8 (shr64 #x6564756c636e69 (wrap* (wrap-cast u64 index) 8))))
          (source_include_name_p source start (wrap+ index 1))
          0)))

(defun source_include_string (parser root)
  (declare (type (ptr psl_parser) parser) (type usize root) (returns usize))
  (let ((head (deref (field-pointer (parser_node parser root) 'first))))
    (let ((argument (deref (field-pointer (parser_node parser head) 'next))))
      (if (= argument 0) 0
          (let ((node (parser_node parser argument)))
            (if (= (deref (field-pointer node 'kind)) 7)
                (if (= (deref (field-pointer node 'next)) 0) argument 0)
                0))))))

(defun native_source_form_kind (parser source root)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize root) (returns u32) (c-export :c))
  (if (= (source_include_head_p parser source root) 0) 1
      (if (= (source_include_string parser root) 0) 0 2)))

(defun source_string_decoded_size (source cursor end size)
  (declare (type (ptr u8) source) (type usize cursor end size) (returns usize))
  (if (= cursor end) size
      (let ((byte (deref (pointer+ source (wrap-cast isize cursor)))))
        (source_string_decoded_size source
          (wrap+ cursor (if (= byte 92) (wrap-cast usize 2) (wrap-cast usize 1)))
          end (wrap+ size 1)))))

(defun native_source_include_size (parser source root)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize root) (returns usize) (c-export :c))
  (if (= (native_source_form_kind parser source root) 2)
      (let ((node (parser_node parser (source_include_string parser root))))
        (let ((start (deref (field-pointer node 'start))))
          (source_string_decoded_size source (wrap+ start 1)
            (wrap- (wrap+ start (deref (field-pointer node 'length))) 1) 0)))
      (wrap-cast usize 0)))

(defun source_string_copy (source cursor end output index)
  (declare (type (ptr u8) source output) (type usize cursor end index) (returns c-int))
  (if (= cursor end)
      (progn (store (pointer+ output (wrap-cast isize index)) 0) 1)
      (let ((byte (deref (pointer+ source (wrap-cast isize cursor)))))
        (let ((position (if (= byte 92) (wrap+ cursor 1) cursor)))
          (let ((decoded (deref (pointer+ source (wrap-cast isize position)))))
            (if (= decoded 0) 0
                (progn
                  (store (pointer+ output (wrap-cast isize index)) decoded)
                  (source_string_copy source (wrap+ position 1) end output (wrap+ index 1)))))))))

(defun native_source_include_copy (parser source root output capacity)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source output)
           (type usize root capacity) (returns c-int) (c-export :c))
  (if (= (native_source_form_kind parser source root) 2)
      (let ((size (native_source_include_size parser source root)))
        (if (< size capacity)
            (let ((node (parser_node parser (source_include_string parser root))))
              (let ((start (deref (field-pointer node 'start))))
                (source_string_copy source (wrap+ start 1)
                  (wrap- (wrap+ start (deref (field-pointer node 'length))) 1) output 0)))
            0))
      0))
