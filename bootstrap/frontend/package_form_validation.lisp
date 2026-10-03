(include "package_form_names.lisp")

(defun native_package_parser (state)
  (declare (type (ptr native_package_context) state) (returns (ptr psl_parser)))
  (deref (field-pointer state 'parser)))

(defun native_package_next (state reference)
  (declare (type (ptr native_package_context) state) (type usize reference)
           (returns usize))
  (if (= reference 0) 0
      (deref (field-pointer (parser_node (native_package_parser state) reference) 'next))))

(defun native_package_word_bytes_p (env symbol a b c length cursor)
  (declare (type (ptr native_ct_environment) env) (type usize symbol length cursor)
           (type u64 a b c) (returns c-int))
  (if (= cursor length) 1
      (if (= (deref (pointer+ (native_ct_symbol_name env symbol) (wrap-cast isize cursor)))
             (native_ct_upper (native_ct_seed_word_byte a b c 0 0 cursor)))
          (native_package_word_bytes_p env symbol a b c length (wrap+ cursor 1)) 0)))

(defun native_package_keyword_p (state reference a b c length)
  (declare (type (ptr native_package_context) state) (type usize reference length)
           (type u64 a b c) (returns c-int))
  (let ((symbol (ast_symbol_identity (native_package_parser state) reference))
        (env (deref (field-pointer state 'environment))))
    (if (= symbol 0) 0
        (let ((definition (native_ct_symbol_at env symbol)))
          (if (= (deref (field-pointer definition 'package)) 4)
              (if (= (deref (field-pointer definition 'length)) length)
                  (native_package_word_bytes_p env symbol a b c length 0) 0) 0)))))

(defun native_package_option_kind (state option)
  (declare (type (ptr native_package_context) state) (type usize option) (returns u32))
  (let ((node (parser_node (native_package_parser state) option)))
    (if (= (deref (field-pointer node 'kind)) 1)
        (let ((head (deref (field-pointer node 'first))))
          (cond
            ((= (native_package_keyword_p state head #x656d616e6b63696e #x73 0 9) 1) 1)
            ((= (native_package_keyword_p state head #x776f64616873 0 0 6) 1) 2)
            ((= (native_package_keyword_p state head #x6e69776f64616873 #x74726f706d692d67 #x6d6f72662d 21) 1) 3)
            ((= (native_package_keyword_p state head #x657375 0 0 3) 1) 4)
            ((= (native_package_keyword_p state head #x662d74726f706d69 #x6d6f72 0 11) 1) 5)
            ((= (native_package_keyword_p state head #x6e7265746e69 0 0 6) 1) 6)
            ((= (native_package_keyword_p state head #x74726f707865 0 0 6) 1) 7)
            (t 0))) 0)))

(defun native_package_validate_names (state argument)
  (declare (type (ptr native_package_context) state) (type usize argument) (returns c-int))
  (if (= argument 0) 1
      (if (= (native_package_name state argument) 1)
          (native_package_validate_names state (native_package_next state argument)) 0)))

(defun native_package_option_mask (kind)
  (declare (type u32 kind) (returns u32))
  (cond ((= kind 1) 2) ((= kind 2) 4) ((= kind 3) 8)
        ((= kind 4) 16) ((= kind 5) 32) ((= kind 6) 64) (t 128)))

(defun native_package_remember_option (state kind)
  (declare (type (ptr native_package_context) state) (type u32 kind) (returns c-int))
  (let ((mask (native_package_option_mask kind)))
    (if (= (bits-and (deref (field-pointer state 'seen)) mask) 0)
        (progn (store (field-pointer state 'seen) (wrap+ (deref (field-pointer state 'seen)) mask)) 1)
        1)))

(defun native_package_validate_options (state option)
  (declare (type (ptr native_package_context) state) (type usize option) (returns c-int))
  (if (= option 0) 1
      (let ((kind (native_package_option_kind state option)))
        (let ((argument (native_package_next state
                          (deref (field-pointer (parser_node (native_package_parser state) option) 'first)))))
          (cond
            ((= kind 0) (native_package_fail state 10))
            ((if (= kind 3) (= argument 0) (if (= kind 5) (= argument 0) nil))
             (native_package_fail state 4))
            ((= (native_package_remember_option state kind) 0) 0)
            (t
             (if (= (native_package_validate_names state argument) 0) 0
                 (native_package_validate_options state (native_package_next state option)))))))))


(defun native_package_names_equal_p (state left right)
  (declare (type (ptr native_package_context) state) (type usize left right) (returns c-int))
  (let ((env (deref (field-pointer state 'environment))))
    (let ((saved (deref (field-pointer env 'name_count))))
      (if (= (native_package_name state left) 0) 0
          (let ((offset (deref (field-pointer state 'offset)))
                (length (deref (field-pointer state 'length))))
            ;; Hold a decoded string while decoding the other designator into
            ;; scratch space. Symbol names already own immutable arena spans.
            (if (= (deref (field-pointer (parser_node (native_package_parser state) left) 'kind)) 7)
                (store (field-pointer env 'name_count) (wrap+ saved length))
                (wrap-cast usize 0))
            (let ((result (if (= (native_package_name state right) 0) (wrap-cast c-int 0)
                              (native_ct_name_matches env offset length
                                 (deref (field-pointer state 'name)) (deref (field-pointer state 'length))))))
              (store (field-pointer env 'name_count) saved)
              result))))))

(defun native_package_names_absent_p (state name arguments)
  (declare (type (ptr native_package_context) state) (type usize name arguments) (returns c-int))
  (if (= arguments 0) 1
      (if (= (native_package_names_equal_p state name arguments) 1)
          (native_package_fail state 3)
          (if (= (deref (field-pointer state 'error)) 0)
              (native_package_names_absent_p state name (native_package_next state arguments)) 0))))

(defun native_package_option_arguments (state option kind)
  (declare (type (ptr native_package_context) state) (type usize option)
           (type u32 kind) (returns usize))
  (let ((argument (native_package_next state
                    (deref (field-pointer (parser_node (native_package_parser state) option) 'first)))))
    (if (if (= kind 3) t (= kind 5)) (native_package_next state argument) argument)))

(defun native_package_disjoint_kinds_p (left right)
  (declare (type u32 left right) (returns c-int))
  (cond
    ((if (= left 6) (= right 7) (if (= left 7) (= right 6) nil)) 1)
    ((= left right) 0)
    ((if (if (= left 2) t (if (= left 3) t (if (= left 5) t (= left 6))))
         (if (= right 2) t (if (= right 3) t (if (= right 5) t (= right 6)))) nil) 1)
    (t 0)))

(defun native_package_disjoint_arguments_p (state arguments others)
  (declare (type (ptr native_package_context) state) (type usize arguments others) (returns c-int))
  (if (= arguments 0) 1
      (if (= (native_package_names_absent_p state arguments others) 0) 0
          (native_package_disjoint_arguments_p state (native_package_next state arguments) others))))

(defun native_package_disjoint_option_p (state option kind later)
  (declare (type (ptr native_package_context) state) (type usize option later)
           (type u32 kind) (returns c-int))
  (if (= later 0) 1
      (let ((other (native_package_option_kind state later)))
        (if (= (native_package_disjoint_kinds_p kind other) 1)
            (if (= (native_package_disjoint_arguments_p state
                     (native_package_option_arguments state option kind)
                     (native_package_option_arguments state later other)) 0) 0
                (native_package_disjoint_option_p state option kind (native_package_next state later)))
            (native_package_disjoint_option_p state option kind (native_package_next state later))))))

(defun native_package_validate_disjoint (state option)
  (declare (type (ptr native_package_context) state) (type usize option) (returns c-int))
  (if (= option 0) 1
      (if (= (native_package_disjoint_option_p state option
                (native_package_option_kind state option) (native_package_next state option)) 0) 0
          (native_package_validate_disjoint state (native_package_next state option)))))

(defun native_package_validate_definition (state options)
  (declare (type (ptr native_package_context) state) (type usize options) (returns c-int))
  (if (= (native_package_validate_options state options) 0) 0
      (native_package_validate_disjoint state options)))
