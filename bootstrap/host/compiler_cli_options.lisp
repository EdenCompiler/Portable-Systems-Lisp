;; CLI parsing owns no source/compiler state and performs no I/O. The record
;; remains caller-owned; a failed parse may contain partial option state.
(defun compiler_cli_text_equal (left right)
  (declare (type (ptr u8) left right) (returns c-int))
  (if (= (ptr-address left) 0) 0
      (if (= (deref left) (deref right))
          (if (= (deref right) 0) 1
              (compiler_cli_text_equal (pointer+ left 1) (pointer+ right 1)))
          0)))

(defun compiler_cli_target_name (text)
  (declare (type (ptr u8) text) (returns c-int))
  (cond
    ((= (compiler_cli_text_equal text (ffi:c-string "x86_64-linux-gnu")) 1) 0)
    ((= (compiler_cli_text_equal text (ffi:c-string "aarch64-linux-gnu")) 1) 1)
    ((= (compiler_cli_text_equal text (ffi:c-string "riscv64-linux-gnu")) 1) 2)
    ((= (compiler_cli_text_equal text (ffi:c-string "x86_64-windows-gnu")) 1) 3)
    (t -1)))

(defun compiler_cli_profile_name (text)
  (declare (type (ptr u8) text) (returns c-int))
  (cond
    ((= (compiler_cli_text_equal text (ffi:c-string "freestanding")) 1) 0)
    ((= (compiler_cli_text_equal text (ffi:c-string "hosted")) 1) 1)
    (t -1)))

(defun compiler_cli_initialize (options)
  (declare (type (ptr native_cli_options) options) (returns c-int))
  (store (field-pointer options 'source) (ptr-from-address (ptr u8) 0))
  (store (field-pointer options 'output) (ptr-from-address (ptr u8) 0))
  (store (field-pointer options 'optimization) 1)
  (store (field-pointer options 'target) 0)
  (store (field-pointer options 'profile) 0)
  (store (field-pointer options 'compile_only) 0)
  (store (field-pointer options 'output_option) 0)
  (store (field-pointer options 'paths) 0)
  (store (field-pointer options 'cursor) 1)
  1)

(defun compiler_cli_store_option (options text kind)
  (declare (type (ptr native_cli_options) options) (type (ptr u8) text)
           (type u32 kind) (returns c-int))
  (let ((value (compiler_option_value text kind)))
    (cond
      ((= kind 1) (store (field-pointer options 'optimization) value))
      ((= kind 2) (store (field-pointer options 'target) value))
      (t (store (field-pointer options 'profile) value)))
    1))

(defun compiler_cli_value_option (options flag value)
  (declare (type (ptr native_cli_options) options) (type (ptr u8) flag value)
           (returns c-int))
  (if (= (ptr-address value) 0) 0
      (cond
        ((= (compiler_cli_text_equal flag (ffi:c-string "-o")) 1)
         (store (field-pointer options 'output) value)
         (store (field-pointer options 'output_option) 1)
         1)
        ((= (compiler_cli_text_equal flag (ffi:c-string "--target")) 1)
         (let ((target (compiler_cli_target_name value)))
           (if (< target 0) 0
               (progn (store (field-pointer options 'target) (wrap-cast u32 target)) 1))))
        (t (let ((profile (compiler_cli_profile_name value)))
             (if (< profile 0) 0
                 (progn (store (field-pointer options 'profile) (wrap-cast u32 profile)) 1)))))))

(defun compiler_cli_path (options text)
  (declare (type (ptr native_cli_options) options) (type (ptr u8) text) (returns c-int))
  (let ((paths (deref (field-pointer options 'paths))))
    (if (= paths 0)
        (progn (store (field-pointer options 'source) text)
               (store (field-pointer options 'paths) 1) 1)
        (if (= paths 1)
            (if (= (deref (field-pointer options 'output_option)) 0)
                (progn (store (field-pointer options 'output) text)
                       (store (field-pointer options 'paths) 2) 1) 0)
            0))))

(defun compiler_cli_takes_value_p (text)
  (declare (type (ptr u8) text) (returns c-int))
  (if (= (compiler_cli_text_equal text (ffi:c-string "-o")) 1) 1
      (if (= (compiler_cli_text_equal text (ffi:c-string "--target")) 1) 1
          (compiler_cli_text_equal text (ffi:c-string "--profile")))))

(defun compiler_cli_argument (options argc argv index)
  (declare (type (ptr native_cli_options) options) (type usize argc index)
           (type (ptr (ptr u8)) argv) (returns usize))
  (let ((text (deref (pointer+ argv (wrap-cast isize index)))))
    (if (= (ptr-address text) 0) 0
        (if (= (compiler_cli_text_equal text (ffi:c-string "-c")) 1)
            (progn (store (field-pointer options 'compile_only) 1) (wrap+ index 1))
            (if (= (compiler_cli_takes_value_p text) 1)
                (if (< (wrap+ index 1) argc)
                    (if (= (compiler_cli_value_option options text
                             (deref (pointer+ argv (wrap-cast isize (wrap+ index 1))))) 1)
                        (wrap+ index 2) 0) 0)
                (let ((kind (compiler_option_kind text)))
                  (if (< 0 kind)
                      (progn (compiler_cli_store_option options text kind) (wrap+ index 1))
                      (if (= (deref text) 45) 0
                          (if (= (compiler_cli_path options text) 1) (wrap+ index 1) 0)))))))))

(defun compiler_cli_complete_p (options)
  (declare (type (ptr native_cli_options) options) (returns c-int))
  (if (= (ptr-address (deref (field-pointer options 'source))) 0) 0
      (if (= (ptr-address (deref (field-pointer options 'output))) 0) 0
          (if (= (deref (field-pointer options 'compile_only)) 1)
              (if (= (deref (field-pointer options 'paths)) 1)
                  (if (= (deref (field-pointer options 'output_option)) 1) 1 0) 0)
              (if (= (deref (field-pointer options 'paths)) 2)
                  (if (= (deref (field-pointer options 'output_option)) 0) 1 0) 0)))))

(defun native_parse_cli_options (argc argv options)
  (declare (type c-int argc) (type (ptr (ptr u8)) argv)
           (type (ptr native_cli_options) options) (returns c-int) (c-export :c))
  (if (< argc 3) 0
      (if (= (ptr-address argv) 0) 0
          (if (= (ptr-address options) 0) 0
              (progn
                (compiler_cli_initialize options)
                (while (if (= (deref (field-pointer options 'cursor)) 0) nil
                           (< (deref (field-pointer options 'cursor)) (wrap-cast usize argc)))
                  (store (field-pointer options 'cursor)
                         (compiler_cli_argument options (wrap-cast usize argc) argv
                           (deref (field-pointer options 'cursor)))))
                (if (= (deref (field-pointer options 'cursor)) (wrap-cast usize argc))
                    (compiler_cli_complete_p options) 0))))))
