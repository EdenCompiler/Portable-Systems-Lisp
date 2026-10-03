(include "../compile_scalar_types.lisp")
(include "package_form_validation.lisp")

(defun native_package_apply_name (state reference kind)
  (declare (type (ptr native_package_context) state) (type usize reference)
           (type u32 kind) (returns c-int))
  (if (= (native_package_name state reference) 0) 0
      (let ((env (deref (field-pointer state 'environment)))
            (package (deref (field-pointer state 'package)))
            (name (deref (field-pointer state 'name)))
            (length (deref (field-pointer state 'length))))
        (cond
          ((= kind 1) (if (= (native_ct_add_alias env package name length) 0) 0 1))
          ((= kind 2) (if (= (native_ct_shadow_name env package name length) 0) 0 1))
          ((= kind 4)
           (let ((used (native_ct_find_package env name length)))
             (if (= used 0) (native_package_fail state 6)
                 (native_ct_use_package env package used))))
          (t (let ((symbol (native_ct_intern env package name length)))
               (if (= symbol 0) 0
                   (if (= kind 7)
                       (if (= (native_ct_export_symbol env package symbol) 0) 0 1) 1))))))))

(defun native_package_apply_import (state reference used kind)
  (declare (type (ptr native_package_context) state) (type usize reference used)
           (type u32 kind) (returns c-int))
  (if (= (native_package_name state reference) 0) 0
      (let ((env (deref (field-pointer state 'environment))))
        (let ((symbol (native_ct_find_symbol env used (deref (field-pointer state 'name))
                                            (deref (field-pointer state 'length)))))
          (if (= symbol 0) (native_package_fail state 4)
              (if (= kind 3)
                  (if (= (native_ct_shadowing_import env (deref (field-pointer state 'package)) symbol) 0) 0 1)
                  (if (= (native_ct_import_symbol env (deref (field-pointer state 'package)) symbol) 0) 0 1)))))))

(defun native_package_apply_arguments (state argument kind used)
  (declare (type (ptr native_package_context) state) (type usize argument used)
           (type u32 kind) (returns c-int))
  (if (= argument 0) 1
      (if (= (if (= kind 3) (native_package_apply_import state argument used kind)
                 (if (= kind 5) (native_package_apply_import state argument used kind)
                     (native_package_apply_name state argument kind))) 1)
          (native_package_apply_arguments state (native_package_next state argument) kind used) 0)))

(defun native_package_apply_option (state option kind)
  (declare (type (ptr native_package_context) state) (type usize option)
           (type u32 kind) (returns c-int))
  (let ((argument (native_package_next state
                    (deref (field-pointer (parser_node (native_package_parser state) option) 'first)))))
    (if (if (= kind 3) t (= kind 5))
        (let ((used (native_package_find_designator state argument)))
          (if (= used 0) (native_package_fail state 6)
              (native_package_apply_arguments state (native_package_next state argument) kind used)))
        (native_package_apply_arguments state argument kind 0))))

(defun native_package_apply_phase (state option phase)
  (declare (type (ptr native_package_context) state) (type usize option)
           (type u32 phase) (returns c-int))
  (if (= option 0) 1
      (if (= (native_package_option_kind state option) phase)
          (if (= (native_package_apply_option state option phase) 0) 0
              (native_package_apply_phase state (native_package_next state option) phase))
          (native_package_apply_phase state (native_package_next state option) phase))))

(defun native_package_apply_phases (state option phase)
  (declare (type (ptr native_package_context) state) (type usize option)
           (type u32 phase) (returns c-int))
  (if (= phase 8) 1
      (if (= (native_package_apply_phase state option phase) 0) 0
          (native_package_apply_phases state option (wrap+ phase 1)))))

(defun native_package_define (state argument)
  (declare (type (ptr native_package_context) state) (type usize argument) (returns c-int))
  (if (= (native_package_name state argument) 0) 0
      (let ((options (native_package_next state argument)))
        (if (= (native_package_validate_definition state options) 0) 0
            (if (= (native_package_name state argument) 0) 0
                (let ((env (deref (field-pointer state 'environment))))
                  (let ((package (native_ct_make_package env (deref (field-pointer state 'name))
                                                         (deref (field-pointer state 'length)))))
                    (store (field-pointer state 'package) package)
                    (if (= package 0) 0
                        (native_package_apply_phases state options 1)))))))))

(defun native_package_select (state argument)
  (declare (type (ptr native_package_context) state) (type usize argument) (returns c-int))
  (if (= (native_package_next state argument) 0)
      (let ((package (native_package_find_designator state argument)))
        (if (= package 0) (native_package_fail state 6)
            (progn (store (field-pointer (deref (field-pointer state 'environment)) 'current_package) package) 1)))
      (native_package_fail state 4)))

(defun native_source_package_kind (context root)
  (declare (type (ptr native_compile_context) context) (type usize root)
           (returns u32) (c-export :c))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (deref (field-pointer (parser_node parser root) 'kind)) 1)
        (let ((head (deref (field-pointer (parser_node parser root) 'first))))
          (cond
            ((= (ast_builtin_word_p parser (deref (field-pointer context 'source)) head #x616b636170666564 #x6567 10) 1) 1)
            ((= (ast_builtin_word_p parser (deref (field-pointer context 'source)) head #x616b6361702d6e69 #x6567 10) 1) 2)
            (t 0))) 0)))

(defun native_apply_package_form (context root state)
  (declare (type (ptr native_compile_context) context) (type usize root)
           (type (ptr native_package_context) state) (returns c-int) (c-export :c))
  (store (field-pointer state 'parser) (deref (field-pointer context 'parser)))
  (store (field-pointer state 'source) (deref (field-pointer context 'source)))
  (store (field-pointer state 'environment)
         (deref (field-pointer (deref (field-pointer (deref (field-pointer context 'parser)) 'environment)) 'environment)))
  (store (field-pointer state 'error) 0)
  (store (field-pointer state 'seen) 0)
  (let ((argument (native_package_next state
                    (deref (field-pointer (parser_node (native_package_parser state) root) 'first)))))
    (if (= argument 0) (native_package_fail state 4)
        (let ((kind (native_source_package_kind context root)))
          (if (= kind 1) (native_package_define state argument)
              (if (= kind 2) (native_package_select state argument) (native_package_fail state 10)))))))
