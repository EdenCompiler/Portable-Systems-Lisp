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

(defun compiler_cli_initialize (options inputs capacity)
  (declare (type (ptr native_cli_options) options)
           (type (ptr (ptr u8)) inputs) (type usize capacity) (returns c-int))
  (store (field-pointer options 'source) (ptr-from-address (ptr u8) 0))
  (store (field-pointer options 'output) (ptr-from-address (ptr u8) 0))
  (store (field-pointer options 'optimization) 1)
  (store (field-pointer options 'target) 0)
  (store (field-pointer options 'profile) 0)
  (store (field-pointer options 'kind) 0)
  (store (field-pointer options 'emit_specified) 0)
  (store (field-pointer options 'compile_only) 0)
  (store (field-pointer options 'output_option) 0)
  (store (field-pointer options 'paths) 0)
  (store (field-pointer options 'cursor) 1)
  (store (field-pointer options 'link_inputs) inputs)
  (store (field-pointer options 'link_input_count) 0)
  (store (field-pointer options 'link_input_capacity) capacity)
  (store (field-pointer options 'help_requested) 0)
  (store (field-pointer options 'parse_error) 0)
  (store (field-pointer options 'parse_error_text) (ptr-from-address (ptr u8) 0))
  1)

(defun compiler_cli_set_error (options kind text)
  (declare (type (ptr native_cli_options) options) (type u32 kind)
           (type (ptr u8) text) (returns c-int))
  (store (field-pointer options 'parse_error) kind)
  (store (field-pointer options 'parse_error_text) text)
  0)

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
        ((= (compiler_cli_text_equal flag (ffi:c-string "--profile")) 1)
         (let ((profile (compiler_cli_profile_name value)))
             (if (< profile 0) 0
                 (progn (store (field-pointer options 'profile) (wrap-cast u32 profile)) 1))))
        (t 0))))

(defun compiler_cli_emit_kind (text)
  (declare (type (ptr u8) text) (returns c-int))
  (cond
    ((= (compiler_cli_text_equal text (ffi:c-string "exe")) 1) 0)
    ((= (compiler_cli_text_equal text (ffi:c-string "static")) 1) 1)
    ((= (compiler_cli_text_equal text (ffi:c-string "shared")) 1) 2)
    (t -1)))

(defun compiler_cli_add_link_input (options value)
  (declare (type (ptr native_cli_options) options) (type (ptr u8) value)
           (returns c-int))
  (let ((count (deref (field-pointer options 'link_input_count)))
        (capacity (deref (field-pointer options 'link_input_capacity)))
        (inputs (deref (field-pointer options 'link_inputs))))
    (if (= (ptr-address value) 0) 0
        (if (if (< count capacity) (< 0 (ptr-address inputs)) nil)
            (progn
              (store (pointer+ inputs (wrap-cast isize count)) value)
              (store (field-pointer options 'link_input_count) (wrap+ count 1))
              1)
            0))))

(defun compiler_cli_prefix_equal (text prefix remaining)
  (declare (type (ptr u8) text prefix) (type usize remaining)
           (returns c-int))
  (if (= remaining 0) 1
      (if (= (deref text) (deref prefix))
          (if (= (deref text) 0) 0
              (compiler_cli_prefix_equal (pointer+ text 1)
                                         (pointer+ prefix 1)
                                         (wrap- remaining 1)))
          0)))

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
          (if (= (compiler_cli_text_equal text (ffi:c-string "--profile")) 1) 1
              (if (= (compiler_cli_text_equal text (ffi:c-string "--emit")) 1) 1
                  (compiler_cli_text_equal text
                                           (ffi:c-string "--link-input")))))))

(defun compiler_cli_add_emit (options text)
  (declare (type (ptr native_cli_options) options) (type (ptr u8) text)
           (returns c-int))
  (let ((kind (compiler_cli_emit_kind text)))
    (if (< kind 0) 0
        (progn
          (store (field-pointer options 'kind) (wrap-cast u32 kind))
          (store (field-pointer options 'emit_specified) 1)
          1))))

(defun compiler_cli_input_arena_valid_p (inputs capacity)
  (declare (type (ptr (ptr u8)) inputs) (type usize capacity)
           (returns c-int))
  (if (= capacity 0)
      (if (= (ptr-address inputs) 0) 1 0)
      (if (= (ptr-address inputs) 0) 0 1)))

(defun compiler_cli_argument (options argc argv index)
  (declare (type (ptr native_cli_options) options) (type usize argc index)
           (type (ptr (ptr u8)) argv) (returns usize))
  (let ((text (deref (pointer+ argv (wrap-cast isize index)))))
    (if (= (ptr-address text) 0) 0
        (if (if (= (compiler_cli_text_equal text (ffi:c-string "--help")) 1)
                t (= (compiler_cli_text_equal text (ffi:c-string "-h")) 1))
            (progn (store (field-pointer options 'help_requested) 1) argc)
        (if (= (compiler_cli_text_equal text (ffi:c-string "-c")) 1)
            (progn (store (field-pointer options 'compile_only) 1) (wrap+ index 1))
            (if (= (compiler_cli_takes_value_p text) 1)
                (if (< (wrap+ index 1) argc)
                    (let ((value (deref (pointer+ argv
                                      (wrap-cast isize (wrap+ index 1))))))
                      (if (= (if (= (compiler_cli_text_equal text
                                      (ffi:c-string "--link-input")) 1)
                              (compiler_cli_add_link_input options value)
                              (if (= (compiler_cli_text_equal text
                                          (ffi:c-string "--emit")) 1)
                                  (compiler_cli_add_emit options value)
                                  (compiler_cli_value_option options text value))) 1)
                          (wrap+ index 2)
                          (wrap-cast usize (compiler_cli_set_error options 1 text))))
                  (wrap-cast usize (compiler_cli_set_error options 2 text)))
                (if (= (compiler_cli_prefix_equal text
                             (ffi:c-string "--link-input=") 13) 1)
                    (if (= (compiler_cli_add_link_input
                            options (pointer+ text 13)) 1)
                        (wrap+ index 1) 0)
                    (if (= (compiler_cli_prefix_equal text
                                 (ffi:c-string "--emit=") 7) 1)
                        (if (= (compiler_cli_add_emit options
                                     (pointer+ text 7)) 1)
                            (wrap+ index 1) 0)
                        (let ((kind (compiler_option_kind text)))
                          (if (< 0 kind)
                              (progn (compiler_cli_store_option options text kind)
                                     (wrap+ index 1))
                              (if (= (deref text) 45)
                                  (wrap-cast usize (compiler_cli_set_error options 1 text))
                                  (if (= (compiler_cli_path options text) 1)
                                      (wrap+ index 1)
                                      (wrap-cast usize (compiler_cli_set_error options 3 text))))))))))))))

(defun compiler_cli_complete_p (options)
  (declare (type (ptr native_cli_options) options) (returns c-int))
  (if (= (ptr-address (deref (field-pointer options 'source))) 0) 0
      (if (= (ptr-address (deref (field-pointer options 'output))) 0) 0
          (if (= (deref (field-pointer options 'compile_only)) 1)
              (if (if (= (deref (field-pointer options 'paths)) 1)
                      (= (deref (field-pointer options 'output_option)) 1) nil)
                  (if (= (deref (field-pointer options 'emit_specified)) 0)
                      (if (= (deref (field-pointer options 'link_input_count)) 0)
                          1 0) 0) 0)
              (if (= (deref (field-pointer options 'paths)) 1)
                  (if (= (deref (field-pointer options 'output_option)) 1)
                      1 0)
                  (if (= (deref (field-pointer options 'paths)) 2)
                      (if (= (deref (field-pointer options 'output_option)) 0)
                          (if (= (deref (field-pointer options 'emit_specified)) 1)
                              1
                              (if (= (deref (field-pointer options 'link_input_count)) 0)
                                  1 0)) 0) 0))))))

(defun compiler_cli_failure_kind (options)
  (declare (type (ptr native_cli_options) options) (returns u32))
  (if (if (= (ptr-address (deref (field-pointer options 'source))) 0)
          t (= (ptr-address (deref (field-pointer options 'output))) 0)) 4
      (if (= (deref (field-pointer options 'compile_only)) 1)
          (if (= (deref (field-pointer options 'emit_specified)) 1) 5
              (if (< 0 (deref (field-pointer options 'link_input_count))) 6 4))
          4)))

(defun native_parse_cli_options_with_inputs (argc argv options inputs capacity)
  (declare (type c-int argc) (type (ptr (ptr u8)) argv)
           (type (ptr native_cli_options) options)
           (type (ptr (ptr u8)) inputs) (type usize capacity)
           (returns c-int) (c-export :c))
  (if (< argc 1) 0
      (if (= (ptr-address argv) 0) 0
          (if (= (ptr-address options) 0) 0
              (if (= (compiler_cli_input_arena_valid_p inputs capacity) 0) 0
                  (progn
                    (compiler_cli_initialize options inputs capacity)
                    (while (if (= (deref (field-pointer options 'cursor)) 0) nil
                               (< (deref (field-pointer options 'cursor))
                                  (wrap-cast usize argc)))
                      (store (field-pointer options 'cursor)
                             (compiler_cli_argument options (wrap-cast usize argc)
                               argv (deref (field-pointer options 'cursor)))))
                    (if (= (deref (field-pointer options 'cursor))
                           (wrap-cast usize argc))
                        (if (= (deref (field-pointer options 'help_requested)) 1) 1
                            (if (= (compiler_cli_complete_p options) 1) 1
                                (compiler_cli_set_error options
                                  (compiler_cli_failure_kind options)
                                  (ptr-from-address (ptr u8) 0))))
                        (if (= (deref (field-pointer options 'parse_error)) 0)
                            (compiler_cli_set_error options 1
                              (deref (pointer+ argv (wrap-cast isize
                                (deref (field-pointer options 'cursor)))))) 0))))))))

(defun native_parse_cli_options (argc argv options)
  (declare (type c-int argc) (type (ptr (ptr u8)) argv)
           (type (ptr native_cli_options) options) (returns c-int) (c-export :c))
  (native_parse_cli_options_with_inputs argc argv options
    (ptr-from-address (ptr (ptr u8)) 0) 0))
