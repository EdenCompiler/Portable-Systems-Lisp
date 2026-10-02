(include "seed_catalogue.lisp")
(defun native_ct_seed_package (env expected length a b)
  (declare (type (ptr native_ct_environment) env) (type usize expected length)
           (type u64 a b) (returns c-int))
  (if (= (native_ct_names_room_p env (wrap* length 2)) 0)
      (progn (native_ct_fail env 1) 0)
      (let ((start (deref (field-pointer env 'name_count))))
        (while (< (wrap- (deref (field-pointer env 'name_count)) start) length)
          (let ((next (deref (field-pointer env 'name_count))))
            (store (pointer+ (deref (field-pointer env 'names)) (wrap-cast isize next))
                   (native_ct_seed_word_byte a b 0 0 0 (wrap- next start)))
            (store (field-pointer env 'name_count) (wrap+ next 1))))
        (let ((package (native_ct_make_package env
                        (pointer+ (deref (field-pointer env 'names)) (wrap-cast isize start)) length)))
          (if (= package expected)
              (progn
                (store (field-pointer (native_ct_package_at env package) 'name) start)
                (store (field-pointer env 'name_count) (wrap+ start length)) 1)
              (progn (native_ct_fail env 2) 0))))))
(defun native_ct_seed_psl_imports (env entry)
  (declare (type (ptr native_ct_environment) env) (type usize entry) (returns c-int))
  (if (= entry 0) 1
      (let ((present (native_ct_presence_at env entry)))
        (let ((symbol (deref (field-pointer present 'symbol))))
          (let ((definition (native_ct_symbol_at env symbol)))
            (if (= (native_ct_find_symbol env 1
                     (pointer+ (deref (field-pointer env 'names))
                                (wrap-cast isize (deref (field-pointer definition 'name))))
                     (deref (field-pointer definition 'length))) 0)
                (native_ct_bind_symbol env 5 symbol 2) (wrap-cast usize 0)))
          (native_ct_seed_psl_imports env (deref (field-pointer present 'next)))))))
(defun native_ct_seed_alias (env package length word)
  (declare (type (ptr native_ct_environment) env) (type usize package length)
           (type u64 word) (returns c-int))
  (if (= (native_ct_names_room_p env (wrap* length 2)) 0)
      (progn (native_ct_fail env 1) 0)
      (let ((start (deref (field-pointer env 'name_count))))
        (while (< (wrap- (deref (field-pointer env 'name_count)) start) length)
          (let ((next (deref (field-pointer env 'name_count))))
            (store (pointer+ (deref (field-pointer env 'names)) (wrap-cast isize next))
                   (native_ct_seed_word_byte word 0 0 0 0 (wrap- next start)))
            (store (field-pointer env 'name_count) (wrap+ next 1))))
        (if (= (native_ct_add_alias env package
                  (pointer+ (deref (field-pointer env 'names)) (wrap-cast isize start)) length) 0) 0
            (progn
              (store (field-pointer (native_ct_alias_at env (deref (field-pointer env 'alias_count))) 'name) start)
              (store (field-pointer env 'name_count) (wrap+ start length)) 1)))))
(defun native_ct_seed_packages (env)
  (declare (type (ptr native_ct_environment) env) (returns c-int))
  (if (= (native_ct_seed_package env 1 11 #x4c2d4e4f4d4d4f43 #x505349) 0) 0
      (if (= (native_ct_seed_package env 2 3 #x4c5350 0) 0) 0
          (if (= (native_ct_seed_package env 3 7 #x4946462e4c5350 0) 0) 0
              (if (= (native_ct_seed_package env 4 7 #x44524f5759454b 0) 0) 0
                  (if (= (native_ct_seed_package env 5 6 #x454352554f53 0) 0) 0
                      (if (= (native_ct_seed_alias env 1 2 #x4c43) 0) 0
                          (native_ct_seed_alias env 3 3 #x494646))))))))
(defun native_ct_seed_exports (env)
  (declare (type (ptr native_ct_environment) env) (returns c-int))
  (if (= (native_ct_seed_common_lisp env) 0) 0
      (if (= (native_ct_seed_psl env) 0) 0 (native_ct_seed_psl_ffi env))))
(defun native_ct_seed_visibility (env)
  (declare (type (ptr native_ct_environment) env) (returns c-int))
  (native_ct_bind_symbol env 2 (native_ct_seed_name env 2 4 #x44414f4c 0 0 0 0) 3)
  (native_ct_bind_symbol env 2 (native_ct_seed_name env 2 6 #x54524f505845 0 0 0 0) 3)
  (if (= (native_ct_link_use env 2 1) 0) 0
      (if (= (native_ct_link_use env 5 1) 0) 0
          (native_ct_seed_psl_imports env
             (deref (field-pointer (native_ct_package_at env 2) 'present))))))

(defun native_ct_seed_empty_p (env)
  (declare (type (ptr native_ct_environment) env) (returns c-int))
  (cond
    ((< 0 (deref (field-pointer env 'name_count))) 0)
    ((< 0 (deref (field-pointer env 'package_count))) 0)
    ((< 0 (deref (field-pointer env 'symbol_count))) 0)
    ((< 0 (deref (field-pointer env 'present_count))) 0)
    ((< 0 (deref (field-pointer env 'use_count))) 0)
    ((< 0 (deref (field-pointer env 'alias_count))) 0)
    (t 1)))

(defun native_ct_seed_standard (env)
  (declare (type (ptr native_ct_environment) env) (returns c-int) (c-export :c))
  (if (= (deref (field-pointer env 'error)) 0)
      (if (= (native_ct_seed_empty_p env) 1)
          (if (= (native_ct_seed_packages env) 0) 0
              (progn
                (store (field-pointer env 'keyword_package) 4)
                (store (field-pointer env 'current_package) 5)
                (if (= (native_ct_seed_exports env) 0) 0
                    (if (= (native_ct_seed_visibility env) 0) 0
                        (progn
                          (store (field-pointer env 'nil_symbol)
                                 (native_ct_seed_name env 1 3 #x4c494e 0 0 0 0))
                          (store (field-pointer env 'true_symbol)
                                 (native_ct_seed_name env 1 1 #x54 0 0 0 0))
                          (if (= (deref (field-pointer env 'error)) 0) 1 0))))))
          (progn (native_ct_fail env 2) 0))
      0))
