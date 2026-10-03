(include "read_symbols.lisp")

(defun native_ct_symbol_name (env symbol)
  (declare (type (ptr native_ct_environment) env) (type usize symbol)
           (returns (ptr u8)))
  (pointer+ (deref (field-pointer env 'names))
            (wrap-cast isize (deref (field-pointer (native_ct_symbol_at env symbol) 'name)))))

(defun native_ct_presence_for_symbol (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize))
  (native_ct_find_present env package (native_ct_symbol_name env symbol)
    (deref (field-pointer (native_ct_symbol_at env symbol) 'length)) 0))

(defun native_ct_accessible_symbol (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize))
  (native_ct_find_symbol env package (native_ct_symbol_name env symbol)
    (deref (field-pointer (native_ct_symbol_at env symbol) 'length))))

(defun native_ct_package_symbol_valid_p (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns c-int))
  (if (= (deref (field-pointer env 'error)) 0)
      (if (= (native_ct_package_valid_p env package) 1)
          (if (= (native_ct_symbol_valid_p env symbol) 1) 1
              (progn (native_ct_fail env 4) 0))
          (progn (native_ct_fail env 4) 0))
      0))

(defun native_ct_import_commit (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize))
  (let ((result (if (= (native_ct_presence_for_symbol env package symbol) 0)
                    (native_ct_add_presence env package symbol 0) symbol)))
    (if (= result 0) 0
        (let ((definition (native_ct_symbol_at env symbol)))
          (if (= (deref (field-pointer definition 'package)) 0)
              (store (field-pointer definition 'package) package) (wrap-cast usize 0))
          result))))

(defun native_ct_import_symbol (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize) (c-export :c))
  (if (= (native_ct_package_symbol_valid_p env package symbol) 0) 0
      (let ((prior (native_ct_accessible_symbol env package symbol)))
        (if (= (deref (field-pointer env 'error)) 0)
            (if (if (= prior 0) t (= prior symbol))
                (native_ct_import_commit env package symbol)
                (native_ct_fail env 3))
            0))))

(defun native_ct_candidate_visible_p (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns c-int))
  (let ((present (native_ct_presence_for_symbol env package symbol)))
    (if (< 0 present)
        (let ((entry (native_ct_presence_at env present)))
          (if (= (bits-and (deref (field-pointer entry 'flags)) 2) 2) 1
              (if (= (deref (field-pointer entry 'symbol)) symbol) 1 0)))
        (let ((prior (native_ct_accessible_symbol env package symbol)))
          (if (= (deref (field-pointer env 'error)) 0)
              (if (if (= prior 0) t (= prior symbol)) 1 0)
              0)))))

(defun native_ct_validate_use_exports (env package entry)
  (declare (type (ptr native_ct_environment) env) (type usize package entry)
           (returns c-int))
  (if (= entry 0) 1
      (let ((present (native_ct_presence_at env entry)))
        (if (= (bits-and (deref (field-pointer present 'flags)) 1) 1)
            (if (= (native_ct_candidate_visible_p env package
                      (deref (field-pointer present 'symbol))) 0)
                (progn (native_ct_fail env 3) 0)
                (native_ct_validate_use_exports env package (deref (field-pointer present 'next))))
            (native_ct_validate_use_exports env package (deref (field-pointer present 'next)))))))

(defun native_ct_use_package (env package used)
  (declare (type (ptr native_ct_environment) env) (type usize package used)
           (returns c-int) (c-export :c))
  (if (= (deref (field-pointer env 'error)) 0)
      (if (= (native_ct_package_valid_p env package) 0)
          (progn (native_ct_fail env 4) 0)
          (if (= (native_ct_package_valid_p env used) 0)
              (progn (native_ct_fail env 4) 0)
              (if (= package (deref (field-pointer env 'keyword_package)))
                  (progn (native_ct_fail env 10) 0)
                  (if (= (native_ct_has_use env
                           (deref (field-pointer (native_ct_package_at env package) 'uses)) used) 1) 1
                      (if (= (native_ct_validate_use_exports env package
                               (deref (field-pointer (native_ct_package_at env used) 'present))) 0) 0
                          (native_ct_link_use env package used))))))
      0))

(defun native_ct_validate_export_users (env exporter symbol package)
  (declare (type (ptr native_ct_environment) env) (type usize exporter symbol package)
           (returns c-int))
  (if (< (deref (field-pointer env 'package_count)) package) 1
      (let ((uses (deref (field-pointer (native_ct_package_at env package) 'uses))))
        (if (= (native_ct_has_use env uses exporter) 1)
            (if (= (native_ct_candidate_visible_p env package symbol) 0)
                (progn (native_ct_fail env 3) 0)
                (native_ct_validate_export_users env exporter symbol (wrap+ package 1)))
            (native_ct_validate_export_users env exporter symbol (wrap+ package 1))))))

(defun native_ct_mark_external (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize))
  (let ((present (native_ct_presence_for_symbol env package symbol)))
    (if (= present 0) (native_ct_add_presence env package symbol 1)
        (let ((entry (native_ct_presence_at env present)))
          (if (= (bits-and (deref (field-pointer entry 'flags)) 1) 0)
              (store (field-pointer entry 'flags) (wrap+ (deref (field-pointer entry 'flags)) 1))
              (wrap-cast u32 0))
          symbol))))

(defun native_ct_export_symbol (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize) (c-export :c))
  (if (= (native_ct_package_symbol_valid_p env package symbol) 0) 0
      (if (= (native_ct_accessible_symbol env package symbol) symbol)
          (if (= (native_ct_validate_export_users env package symbol 1) 0) 0
              (native_ct_mark_external env package symbol))
          (native_ct_fail env 3))))

(defun native_ct_mark_shadowing (env entry)
  (declare (type (ptr native_ct_environment) env) (type usize entry)
           (returns usize))
  (let ((present (native_ct_presence_at env entry)))
    (if (= (bits-and (deref (field-pointer present 'flags)) 2) 0)
        (store (field-pointer present 'flags) (wrap+ (deref (field-pointer present 'flags)) 2))
        (wrap-cast u32 0))
    (deref (field-pointer present 'symbol))))

(defun native_ct_shadow_name (env package name length)
  (declare (type (ptr native_ct_environment) env) (type usize package length)
           (type (ptr u8) name) (returns usize) (c-export :c))
  (if (= (deref (field-pointer env 'error)) 0)
      (if (= (native_ct_package_valid_p env package) 0) (native_ct_fail env 4)
          (let ((present (native_ct_find_present env package name length 0)))
            (if (< 0 present) (native_ct_mark_shadowing env present)
                (let ((symbol (native_ct_new_symbol env package name length)))
                  (if (= symbol 0) 0
                      (native_ct_mark_shadowing env
                        (native_ct_presence_for_symbol env package symbol)))))))
      0))

(defun native_ct_detach_home (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns c-int))
  (let ((definition (native_ct_symbol_at env symbol)))
    (if (= (deref (field-pointer definition 'package)) package)
        (store (field-pointer definition 'package) 0)
        (wrap-cast usize 0))
    1))

(defun native_ct_shadowing_import (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize) (c-export :c))
  (if (= (native_ct_package_symbol_valid_p env package symbol) 0) 0
      (let ((present (native_ct_presence_for_symbol env package symbol)))
        (if (= present 0) (native_ct_add_presence env package symbol 2)
            (let ((entry (native_ct_presence_at env present)))
              (let ((prior (deref (field-pointer entry 'symbol))))
                (if (= prior symbol) (native_ct_mark_shadowing env present)
                    (progn
                      (native_ct_detach_home env package prior)
                      (store (field-pointer entry 'symbol) symbol)
                      (store (field-pointer entry 'flags) 2)
                      symbol))))))))

(defun native_ct_unintern_visible_p (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns c-int))
  (native_ct_find_used env (native_ct_symbol_name env symbol)
    (deref (field-pointer (native_ct_symbol_at env symbol) 'length))
    (deref (field-pointer (native_ct_package_at env package) 'uses)) 0)
  (if (= (deref (field-pointer env 'error)) 0) 1 0))

(defun native_ct_unlink_bucket_entry (env link reference)
  (declare (type (ptr native_ct_environment) env) (type (ptr usize) link)
           (type usize reference) (returns c-int))
  (let ((entry (deref link)))
    (if (= entry 0) 0
        (let ((present (native_ct_presence_at env entry)))
          (if (= entry reference)
              (progn (store link (deref (field-pointer present 'bucket_next))) 1)
              (native_ct_unlink_bucket_entry env (field-pointer present 'bucket_next) reference))))))

(defun native_ct_unlink_index (env package reference)
  (declare (type (ptr native_ct_environment) env) (type usize package reference)
           (returns c-int))
  (if (= (deref (field-pointer env 'bucket_count)) 0) 1
      (let ((symbol (deref (field-pointer (native_ct_presence_at env reference) 'symbol))))
        (native_ct_unlink_bucket_entry env
           (native_ct_bucket env package (native_ct_symbol_name env symbol)
              (deref (field-pointer (native_ct_symbol_at env symbol) 'length))) reference))))

(defun native_ct_unlink_presence (env package symbol entry prior)
  (declare (type (ptr native_ct_environment) env)
           (type usize package symbol entry prior) (returns c-int))
  (if (= entry 0) 0
      (let ((present (native_ct_presence_at env entry)))
        (if (= (deref (field-pointer present 'symbol)) symbol)
            (progn
              (native_ct_unlink_index env package entry)
              (if (= prior 0)
                  (store (field-pointer (native_ct_package_at env package) 'present)
                         (deref (field-pointer present 'next)))
                  (store (field-pointer (native_ct_presence_at env prior) 'next)
                         (deref (field-pointer present 'next))))
              (native_ct_detach_home env package symbol)
              1)
            (native_ct_unlink_presence env package symbol
               (deref (field-pointer present 'next)) entry)))))

(defun native_ct_unintern_symbol (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns c-int) (c-export :c))
  (if (= (native_ct_package_symbol_valid_p env package symbol) 0) 0
      (let ((present (native_ct_presence_for_symbol env package symbol)))
        (if (= present 0) 0
            (if (= (deref (field-pointer (native_ct_presence_at env present) 'symbol)) symbol)
                (if (= (native_ct_unintern_visible_p env package symbol) 0) 0
                    (native_ct_unlink_presence env package symbol
                       (deref (field-pointer (native_ct_package_at env package) 'present)) 0))
                0)))))

(defun native_ct_unlink_use (env link used)
  (declare (type (ptr native_ct_environment) env) (type (ptr usize) link)
           (type usize used) (returns c-int))
  (let ((reference (deref link)))
    (if (= reference 0) 1
        (let ((entry (native_ct_use_at env reference)))
          (if (= (deref (field-pointer entry 'package)) used)
              (progn (store link (deref (field-pointer entry 'next))) 1)
              (native_ct_unlink_use env (field-pointer entry 'next) used))))))

(defun native_ct_unuse_package (env package used)
  (declare (type (ptr native_ct_environment) env) (type usize package used)
           (returns c-int) (c-export :c))
  (if (= (deref (field-pointer env 'error)) 0)
      (if (= (native_ct_package_valid_p env package) 0)
          (progn (native_ct_fail env 4) 0)
          (if (= (native_ct_package_valid_p env used) 0)
              (progn (native_ct_fail env 4) 0)
              (native_ct_unlink_use env
                (field-pointer (native_ct_package_at env package) 'uses) used)))
      0))

(defun native_ct_unexport_symbol (env package symbol)
  (declare (type (ptr native_ct_environment) env) (type usize package symbol)
           (returns usize) (c-export :c))
  (if (= (native_ct_package_symbol_valid_p env package symbol) 0) 0
      (if (= (native_ct_accessible_symbol env package symbol) symbol)
          (let ((present (native_ct_presence_for_symbol env package symbol)))
            (if (= present 0) symbol
                (let ((entry (native_ct_presence_at env present)))
                  (store (field-pointer entry 'flags) (bits-and (deref (field-pointer entry 'flags)) 2))
                  symbol)))
          (native_ct_fail env 3))))
