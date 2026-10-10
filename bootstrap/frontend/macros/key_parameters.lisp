(include "types.lisp")

(defun native_macro_key_marker_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (ast_builtin_word_p (native_macro_parser registry) (deref (field-pointer registry 'source)) reference #x79656b26 0 4))

(defun native_macro_allow_keys_name_p (env symbol index)
  (declare (type (ptr native_ct_environment) env) (type usize symbol index) (returns c-int))
  (if (= index 17) 1
      (if (= (deref (pointer+ (native_ct_symbol_name env symbol) (wrap-cast isize index)))
             (native_ct_seed_word_byte #x4f2d574f4c4c4126 #x59454b2d52454854 #x53 0 0 index))
          (native_macro_allow_keys_name_p env symbol (wrap+ index 1)) 0)))

(defun native_macro_allow_keys_marker_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((parser (native_macro_parser registry)))
    (let ((symbol (ast_symbol_identity parser reference)))
      (if (= symbol 0) 0
          (let ((env (deref (field-pointer (deref (field-pointer parser 'environment)) 'environment))))
            (let ((definition (native_ct_symbol_at env symbol)))
              (if (if (= (deref (field-pointer definition 'package)) 1)
                      (= (deref (field-pointer definition 'length)) 17) nil)
                  (native_macro_allow_keys_name_p env symbol 0) 0)))))))

(defun native_macro_key_name (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns usize))
  (let ((parser (native_macro_parser registry)))
    (let ((node (parser_node parser reference)))
      (let ((name (if (= (deref (field-pointer node 'kind)) 1) (deref (field-pointer node 'first)) reference)))
        (if (= name 0) 0
            (if (= (deref (field-pointer (parser_node parser name) 'kind)) 1)
                (native_macro_next registry (deref (field-pointer (parser_node parser name) 'first))) name))))))

(defun native_macro_key_explicit (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns usize))
  (let ((parser (native_macro_parser registry)))
    (let ((node (parser_node parser reference)))
      (if (= (deref (field-pointer node 'kind)) 1)
          (let ((name (deref (field-pointer node 'first))))
            (if (= name 0) 0
                (if (= (deref (field-pointer (parser_node parser name) 'kind)) 1)
                    (deref (field-pointer (parser_node parser name) 'first)) 0))) 0))))

(defun native_macro_key_spec_p (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((parser (native_macro_parser registry)))
    (let ((node (parser_node parser reference)))
      (let ((name (native_macro_key_name registry reference)) (explicit (native_macro_key_explicit registry reference)))
        (cond
          ((= (native_macro_parameter_p registry name) 0) 0)
          ((if (< 0 explicit)
               (if (= (ast_symbol_identity parser explicit) 0) t
                   (if (= (native_macro_raw_dot_p registry explicit) 1) t
                       (< 0 (native_macro_next registry name)))) nil) 0)
          ((= (deref (field-pointer node 'kind)) 1)
           (let ((first (deref (field-pointer node 'first))))
             (let ((supplied (native_macro_next registry (native_macro_next registry first))))
               (if (= supplied 0) 1
                   (if (< 0 (native_macro_next registry supplied)) 0
                       (native_macro_parameter_p registry supplied))))))
          (t 1))))))

(defun native_macro_validate_key_step (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((tree (deref (field-pointer registry 'tree))))
    (cond
      ((= (native_macro_aux_marker_p registry reference) 1)
       (native_macro_validate_aux_parameters registry (native_macro_next registry reference)))
      ((= (native_macro_allow_keys_marker_p registry reference) 1)
       (let ((tail (native_macro_next registry reference)))
         (if (= tail 0) (progn (store (field-pointer tree 'cursor) 0) 1)
             (if (= (native_macro_aux_marker_p registry tail) 1)
                 (native_macro_validate_aux_parameters registry (native_macro_next registry tail)) 0))))
      ((= (native_macro_key_spec_p registry reference) 0) 0)
      (t (store (field-pointer tree 'cursor) (native_macro_next registry reference)) 1))))

(defun native_macro_validate_key_parameters (registry reference)
  (declare (type (ptr native_macro_registry) registry) (type usize reference) (returns c-int))
  (let ((tree (deref (field-pointer registry 'tree))))
    (store (field-pointer tree 'cursor) reference)
    (while (if (= (deref (field-pointer registry 'error)) 0) (< 0 (deref (field-pointer tree 'cursor))) nil)
      (if (= (native_macro_validate_key_step registry (deref (field-pointer tree 'cursor))) 1)
          (wrap-cast usize 1) (native_macro_fail registry 10)))
    (if (= (deref (field-pointer registry 'error)) 0) 1 0)))
