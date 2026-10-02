(include "environment/words.lisp")

(defun ast_symbol_identity (parser reference)
  (declare (type (ptr psl_parser) parser) (type usize reference) (returns usize))
  (let ((reader (deref (field-pointer parser 'environment))))
    (if (= (ptr-address reader) 0) 0
        (if (= reference 0) 0
            (if (< (deref (field-pointer reader 'count)) reference) 0
                (deref (field-pointer
                         (pointer+ (deref (field-pointer reader 'identities))
                                   (wrap-cast isize (wrap- reference 1))) 'symbol)))))))

(defun ast_builtin_word_p (parser source reference first last length)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize reference length) (type u64 first last) (returns c-int))
  (if (= reference 0) 0
      (let ((reader (deref (field-pointer parser 'environment))))
    (if (= (ptr-address reader) 0)
        (let ((node (parser_node parser reference)))
          (source_builtin_word_p source (deref (field-pointer node 'start))
             (deref (field-pointer node 'length)) first last length))
        (let ((identity (ast_symbol_identity parser reference)))
          (if (= identity 0) 0
              (if (= identity (native_ct_builtin_symbol
                               (deref (field-pointer reader 'environment)) first last length)) 1 0)))))))

(defun ast_package_word_p (parser reference package first last length)
  (declare (type (ptr psl_parser) parser) (type usize reference package length)
           (type u64 first last) (returns c-int))
  (let ((identity (ast_symbol_identity parser reference))
        (reader (deref (field-pointer parser 'environment))))
    (if (= identity 0) 0
        (if (= identity (native_ct_word_symbol
                         (deref (field-pointer reader 'environment)) package first last length)) 1 0))))
