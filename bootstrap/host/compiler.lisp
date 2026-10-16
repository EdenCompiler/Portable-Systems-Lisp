(include "compiler_diagnostics.lisp")
(include "../target.lisp")
(include "compiler_link.lisp")

(defun compiler_release_c_sources (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (while (< 0 (ptr-address (deref (field-pointer state 'c_sources))))
    (let ((entry (deref (field-pointer state 'c_sources))))
      (store (field-pointer state 'c_sources)
             (ptr-cast (ptr native_c_source_path)
                       (deref (field-pointer entry 'next))))
      (ffi:call free (ptr-cast (ptr void) (deref (field-pointer entry 'path))))
      (ffi:call free (ptr-cast (ptr void) entry))))
  1)

(defun compiler_link_output (state output_path kind link_inputs link_count)
  (declare (type (ptr native_compiler_state) state) (type (ptr u8) output_path)
           (type u32 kind) (type (ptr (ptr u8)) link_inputs)
           (type usize link_count) (returns c-int))
  (if (= (ffi:call native_host_link_supported) 0) 0
      (let ((driver (field-pointer state 'driver)))
        (let ((scanned-roots
                (ffi:call native_host_runtime_roots
                          (deref (field-pointer state 'target))
                          (deref (field-pointer state 'c_sources))
                          link_inputs link_count)))
          (if (= scanned-roots (wrap-cast u64 -1)) 0
              (let ((runtime-roots
                      (native_runtime_mask_union
                       (deref (field-pointer (field-pointer driver 'context)
                                             'runtime_modules))
                       scanned-roots)))
                (ffi:call native_host_link_artifact
                  output_path (field-pointer driver 'object)
                  (deref (field-pointer state 'c_sources))
                  (deref (field-pointer state 'target))
                  (deref (field-pointer state 'profile))
                  (native_runtime_link_dependencies runtime-roots)
                  kind link_inputs link_count)))))))

(defun compiler_publish_compiled_output (state output_path link_requested kind
                                         link_inputs link_count)
  (declare (type (ptr native_compiler_state) state) (type (ptr u8) output_path)
           (type u32 link_requested kind) (type (ptr (ptr u8)) link_inputs)
           (type usize link_count) (returns c-int))
  (if (= link_requested 1)
      (compiler_link_output state output_path kind link_inputs link_count)
      (if (= (ptr-address (deref (field-pointer state 'c_sources))) 0)
          (ffi:call native_host_write_object output_path
                    (field-pointer (field-pointer state 'driver) 'object))
          (ffi:call native_host_merge_c_sources
                    output_path (field-pointer (field-pointer state 'driver) 'object)
                    (deref (field-pointer state 'c_sources))
                    (deref (field-pointer state 'target))))))

(defun compiler_emit_object (state source_path output_path link_requested kind
                             link_inputs link_count)
  (declare (type (ptr native_compiler_state) state) (type (ptr u8) source_path output_path)
           (type u32 link_requested kind) (type (ptr (ptr u8)) link_inputs)
           (type usize link_count)
           (returns c-int))
      (let ((driver (field-pointer state 'driver))
            (result (field-pointer state 'result)))
    (if (= (ffi:call native_compile_unit (field-pointer driver 'context)
                     (field-pointer driver 'object) result) 0)
        (progn
          (compiler_report_unit_error driver result)
          (ffi:call native_host_report_error 3 source_path 0 0)
          1)
        (if (= (compiler_publish_compiled_output state output_path
                                                link_requested kind
                                                link_inputs link_count) 0)
            (compiler_path_error 4 output_path)
            0))))

(defun compiler_load_and_prepare (state source_path output_path link_requested
                                 kind link_inputs link_count)
  (declare (type (ptr native_compiler_state) state) (type (ptr u8) source_path output_path)
           (type u32 link_requested kind) (type (ptr (ptr u8)) link_inputs)
           (type usize link_count)
           (returns c-int))
  (let ((driver (field-pointer state 'driver)))
    (store (field-pointer driver 'source)
      (ffi:call native_read_source_unit source_path (field-pointer driver 'length)
                (field-pointer state 'c_sources)))
    (if (= (ptr-address (deref (field-pointer driver 'source))) 0)
        (compiler_path_error 1 source_path)
        (if (= (ffi:call native_prepare_driver driver) 0)
            (compiler_path_error 2 (ptr-from-address (ptr u8) 0))
            (progn
              (store (field-pointer (field-pointer driver 'context) 'optimization)
                     (deref (field-pointer state 'optimization)))
              (store (field-pointer (field-pointer driver 'context) 'target)
                     (deref (field-pointer state 'target)))
              (store (field-pointer (field-pointer driver 'context) 'profile)
                     (deref (field-pointer state 'profile)))
              (compiler_emit_object state source_path output_path link_requested
                                    kind link_inputs link_count))))))

(defun compiler_run_profile (source_path output_path optimization target profile)
  (declare (type (ptr u8) source_path output_path) (type u32 optimization target profile) (returns c-int))
  (let ((state (ptr-cast (ptr native_compiler_state)
                (ffi:call calloc 1 (sizeof 'native_compiler_state)))))
    (if (= (ptr-address state) 0)
        (compiler_path_error 2 (ptr-from-address (ptr u8) 0))
        (progn
          (store (field-pointer state 'optimization) optimization)
          (store (field-pointer state 'target) target)
          (store (field-pointer state 'profile) profile)
          (let ((status (compiler_load_and_prepare state source_path output_path
                                                   0 0
                                                   (ptr-from-address (ptr (ptr u8)) 0)
                                                   0)))
            (ffi:call native_release_driver (field-pointer state 'driver))
            (compiler_release_c_sources state)
            (ffi:call free (ptr-cast (ptr void) state))
            status)))))

(defun native_run_compiler_profile (source_path output_path optimization target profile)
  (declare (type (ptr u8) source_path output_path) (type u32 optimization target profile)
           (returns c-int) (c-export :c))
  (if (< 1 optimization) (compiler_path_error 5 (ptr-from-address (ptr u8) 0))
      (if (< 1 profile) (compiler_path_error 5 (ptr-from-address (ptr u8) 0))
          (if (= (native_target_valid_p target) 0) (compiler_path_error 5 (ptr-from-address (ptr u8) 0))
              (compiler_run_profile source_path output_path optimization target profile)))))

(defun native_run_compiler_target (source_path output_path optimization target)
  (declare (type (ptr u8) source_path output_path) (type u32 optimization target)
           (returns c-int) (c-export :c))
  (native_run_compiler_profile source_path output_path optimization target 0))

(defun native_run_compiler_options (source_path output_path optimization)
  (declare (type (ptr u8) source_path output_path) (type u32 optimization)
           (returns c-int) (c-export :c))
  (native_run_compiler_target source_path output_path optimization 0))

(defun native_run_compiler (source_path output_path)
  (declare (type (ptr u8) source_path output_path) (returns c-int) (c-export :c))
  (native_run_compiler_options source_path output_path 1))

(defun compiler_parse_optimization (text)
  (declare (type (ptr u8) text) (returns c-int))
  (if (= (deref text) 45)
      (if (= (deref (pointer+ text 1)) 79)
          (let ((digit (deref (pointer+ text 2))))
            (if (if (= digit 48) t (= digit 49))
                (if (= (deref (pointer+ text 3)) 0)
                    (wrap-cast c-int (wrap- digit 48)) -1)
                -1))
          -1)
      -1))

(include "compiler_target_options.lisp")
(include "compiler_profile_options.lisp")
(include "compiler_cli_options.lisp")

(defun compiler_run_cli_state (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((options (field-pointer state 'options)))
    (store (field-pointer state 'optimization) (deref (field-pointer options 'optimization)))
    (store (field-pointer state 'target) (deref (field-pointer options 'target)))
    (store (field-pointer state 'profile) (deref (field-pointer options 'profile)))
    (let ((status (compiler_load_and_prepare state
                    (deref (field-pointer options 'source))
                    (deref (field-pointer options 'output))
                    (if (= (deref (field-pointer options 'compile_only)) 1) 0
                        (if (if (= (deref (field-pointer options 'output_option)) 1)
                                t (= (deref (field-pointer options 'emit_specified)) 1))
                            1 0))
                    (deref (field-pointer options 'kind))
                    (deref (field-pointer options 'link_inputs))
                    (deref (field-pointer options 'link_input_count)))))
      (ffi:call native_release_driver (field-pointer state 'driver))
      (compiler_release_c_sources state)
      (ffi:call free (ptr-cast (ptr void)
                               (deref (field-pointer state 'link_input_storage))))
      (ffi:call free (ptr-cast (ptr void) state))
      status)))

(defun native_compiler_main (argc argv)
  (declare (type c-int argc) (type (ptr (ptr u8)) argv) (returns c-int) (c-export :c))
  (if (= (ptr-address argv) 0) (compiler_path_error 5 (ptr-from-address (ptr u8) 0))
      (if (< argc 1) (compiler_path_error 5 (ptr-from-address (ptr u8) 0))
      (let ((state (ptr-cast (ptr native_compiler_state)
                         (ffi:call calloc 1 (sizeof 'native_compiler_state)))))
            (if (= (ptr-address state) 0)
                (compiler_path_error 2 (ptr-from-address (ptr u8) 0))
                (let ((inputs (ptr-cast (ptr (ptr u8))
                               (ffi:call calloc (wrap-cast usize argc)
                                                 (sizeof '(ptr u8))))))
                  (if (= (ptr-address inputs) 0)
                      (progn (ffi:call free (ptr-cast (ptr void) state))
                             (compiler_path_error 2 (ptr-from-address (ptr u8) 0)))
                      (progn
                        (store (field-pointer state 'link_input_storage) inputs)
                        (if (= (native_parse_cli_options_with_inputs
                                 argc argv (field-pointer state 'options) inputs
                                 (wrap-cast usize argc)) 0)
                            (progn
                              (ffi:call native_host_report_error 20
                                (deref (field-pointer
                                  (field-pointer state 'options) 'parse_error_text))
                                (wrap-cast usize (deref (field-pointer
                                  (field-pointer state 'options) 'parse_error)))
                                (wrap-cast usize 0))
                              (ffi:call free (ptr-cast (ptr void) inputs))
                              (ffi:call free (ptr-cast (ptr void) state))
                              1)
                            (if (= (deref (field-pointer
                                  (field-pointer state 'options) 'help_requested)) 1)
                                (progn
                                  (ffi:call native_host_report_error 19
                                    (ptr-from-address (ptr u8) 0) 0 0)
                                  (ffi:call free (ptr-cast (ptr void) inputs))
                                  (ffi:call free (ptr-cast (ptr void) state))
                                  0)
                                (compiler_run_cli_state state)))))))))))
