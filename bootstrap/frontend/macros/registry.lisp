(include "types.lisp")
(include "tree_copy.lisp")
(include "../environment/operations.lisp")
(include "../symbols.lisp")
(include "../identity_syntax.lisp")

(defun native_macro_fail (registry error)
  (declare (type (ptr native_macro_registry) registry) (type u32 error) (returns usize))
  (if (= (deref (field-pointer registry 'error)) 0)
      (store (field-pointer registry 'error) error) (wrap-cast u32 0))
  0)

(defun native_macro_parser (registry)
  (declare (type (ptr native_macro_registry) registry) (returns (ptr psl_parser)))
  (deref (field-pointer registry 'parser)))

(defun native_macro_definition_at (registry index)
  (declare (type (ptr native_macro_registry) registry) (type usize index)
           (returns (ptr native_macro_definition)))
  (pointer+ (deref (field-pointer registry 'definitions)) (wrap-cast isize (wrap- index 1))))

(defun native_macro_lookup_from (registry symbol index)
  (declare (type (ptr native_macro_registry) registry) (type usize symbol index) (returns usize))
  (if (< (deref (field-pointer registry 'count)) index) 0
      (if (= (deref (field-pointer (native_macro_definition_at registry index) 'symbol)) symbol) index
          (native_macro_lookup_from registry symbol (wrap+ index 1)))))

(defun native_macro_lookup (registry symbol)
  (declare (type (ptr native_macro_registry) registry) (type usize symbol)
           (returns usize) (c-export :c))
  (if (= symbol 0) 0 (native_macro_lookup_from registry symbol 1)))

(defun native_macro_next (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns usize))
  (if (= reference 0) 0
      (deref (field-pointer (parser_node (native_macro_parser registry) reference) 'next))))

(defun native_macro_raw_dot_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (if (= reference 0) 0
      (let ((node (parser_node (native_macro_parser registry) reference)))
        (if (= (deref (field-pointer node 'kind)) 8)
            (if (= (deref (field-pointer node 'length)) 1)
                (if (= (deref (pointer+ (deref (field-pointer registry 'source))
                                      (wrap-cast isize (deref (field-pointer node 'start))))) 46) 1 0) 0) 0))))

(defun native_macro_parameter_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((symbol (ast_symbol_identity (native_macro_parser registry) reference)))
    (if (if (= symbol 0) t (= (native_macro_raw_dot_p registry reference) 1)) 0
        (let ((env (deref (field-pointer (deref (field-pointer (native_macro_parser registry) 'environment)) 'environment))))
          (cond
            ((= symbol (deref (field-pointer env 'nil_symbol))) 0)
            ((= symbol (deref (field-pointer env 'true_symbol))) 0)
            ((= (deref (field-pointer (native_ct_symbol_at env symbol) 'package))
                (deref (field-pointer env 'keyword_package))) 0)
            ((= (deref (field-pointer (native_ct_symbol_at env symbol) 'length)) 0) 1)
            ((if (= (deref (field-pointer (native_ct_symbol_at env symbol) 'package)) 1)
                 (= (deref (native_ct_symbol_name env symbol)) 38) nil) 0)
            (t 1))))))

(defun native_macro_rest_marker_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((parser (native_macro_parser registry)) (source (deref (field-pointer registry 'source))))
    (if (= (ast_builtin_word_p parser source reference #x7473657226 0 5) 1) 1
        (ast_builtin_word_p parser source reference #x79646f6226 0 5))))

(defun native_macro_parameter_list_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (if (= reference 0) 0
      (if (= (deref (field-pointer (parser_node (native_macro_parser registry) reference) 'kind)) 1) 1
          (ast_builtin_word_p (native_macro_parser registry) (deref (field-pointer registry 'source))
                             reference #x6c696e 0 3))))

(defun native_macro_validate_parameter_step (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((tree (deref (field-pointer registry 'tree))))
    (if (= (native_macro_rest_marker_p registry reference) 1)
        (let ((name (native_macro_next registry reference)))
          (if (= (native_macro_parameter_p registry name) 0) 0
              (if (= (native_macro_next registry name) 0)
                  (progn (store (field-pointer tree 'cursor) 0) 1) 0)))
        (if (= (native_macro_parameter_p registry reference) 0) 0
            (progn (store (field-pointer tree 'cursor) (native_macro_next registry reference)) 1)))))

(defun native_macro_validate_parameters (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((tree (deref (field-pointer registry 'tree))))
    (store (field-pointer tree 'cursor) reference)
    (while (if (= (deref (field-pointer registry 'error)) 0)
               (< 0 (deref (field-pointer tree 'cursor))) nil)
      (if (= (native_macro_validate_parameter_step registry (deref (field-pointer tree 'cursor))) 1)
          (wrap-cast usize 1) (native_macro_fail registry 10)))
    (if (= (deref (field-pointer registry 'error)) 0) 1 0)))

(defun native_macro_publish (registry symbol parameters body)
  (declare (type (ptr native_macro_registry) registry) (type usize symbol parameters body) (returns usize))
  (let ((prior (native_macro_lookup registry symbol)))
    (let ((index (if (= prior 0) (wrap+ (deref (field-pointer registry 'count)) 1) prior)))
      (if (< (deref (field-pointer registry 'capacity)) index) (native_macro_fail registry 1)
          (let ((definition (native_macro_definition_at registry index)))
            (store (field-pointer definition 'symbol) symbol)
            (store (field-pointer definition 'parameters) parameters)
            (store (field-pointer definition 'body) body)
            (if (= prior 0) (store (field-pointer registry 'count) index) (wrap-cast usize 0))
            index)))))

(defun native_macro_name_prefix_p (env symbol a b length index)
  (declare (type (ptr native_ct_environment) env) (type usize symbol length index)
           (type u64 a b) (returns c-int))
  (if (= index length) 1
      (if (= (native_ct_upper (deref (pointer+ (native_ct_symbol_name env symbol) (wrap-cast isize index))))
             (native_ct_seed_word_byte a b 0 0 0 index))
          (native_macro_name_prefix_p env symbol a b length (wrap+ index 1)) 0)))

(defun native_macro_user_name_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((symbol (ast_symbol_identity (native_macro_parser registry) reference)))
    (if (if (= symbol 0) t (= (native_macro_raw_dot_p registry reference) 1)) 0
        (let ((env (deref (field-pointer (deref (field-pointer (native_macro_parser registry) 'environment)) 'environment))))
          (let ((definition (native_ct_symbol_at env symbol)))
            (let ((package (deref (field-pointer definition 'package)))
                  (length (deref (field-pointer definition 'length))))
              (cond
                ((if (< 0 package) (< package 4) nil) 0)
                ((if (< length 7) nil (= (native_macro_name_prefix_p env symbol #x5f54525f4c5350 0 7 0) 1)) 0)
                ((if (< length 11) nil (= (native_macro_name_prefix_p env symbol #x424d414c5f4c5350 #x5f4144 11 0) 1)) 0)
                (t 1))))))))

(defun native_macro_register_parts (registry name parameters body)
  (declare (type (ptr native_macro_registry) registry) (type usize name parameters body)
           (returns usize))
  (let ((parser (native_macro_parser registry)))
    (cond
      ((= (native_macro_user_name_p registry name) 0) (native_macro_fail registry 4))
      ((= parameters 0) (native_macro_fail registry 4))
      ((= body 0) (native_macro_fail registry 4))
      ((< 0 (native_macro_next registry body)) (native_macro_fail registry 10))
      ((= (native_macro_parameter_list_p registry parameters) 0) (native_macro_fail registry 10))
      ((= (native_macro_validate_parameters registry (deref (field-pointer (parser_node parser parameters) 'first))) 0)
       (native_macro_fail registry 10))
      (t (native_macro_publish registry (ast_symbol_identity parser name) parameters body)))))

(defun native_macro_register (registry root)
  (declare (type (ptr native_macro_registry) registry) (type usize root)
           (returns usize) (c-export :c))
  (let ((parser (native_macro_parser registry)))
    (if (< 0 (deref (field-pointer registry 'error))) 0
        (if (= (native_tree_verify (deref (field-pointer registry 'tree)) root) 0)
            (native_macro_fail registry 4)
            (let ((head (deref (field-pointer (parser_node parser root) 'first))))
              (if (= (ast_builtin_word_p parser (deref (field-pointer registry 'source)) head
                         #x6f7263616d666564 0 8) 0) (native_macro_fail registry 10)
                  (let ((name (native_macro_next registry head)))
                    (let ((parameters (native_macro_next registry name)))
                      (native_macro_register_parts registry name parameters (native_macro_next registry parameters))))))))))
