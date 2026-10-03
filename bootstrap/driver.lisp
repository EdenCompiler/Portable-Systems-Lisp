(include "compile_scalar.lisp")

(include "unit_types.lisp")
(include "frontend/environment/resolve.lisp")
(include "frontend/package_forms.lisp")
(include "frontend/layout_packed.lisp")

(defun native_unit_fail (result phase)
  (declare (type (ptr native_unit_result) result) (type usize phase)
           (returns c-int))
  (store (field-pointer result 'phase) phase)
  0)

(defun native_collect_form (context result)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result) (returns c-int))
  (let ((signatures (deref (field-pointer context 'signatures)))
        (form (deref (field-pointer result 'form))))
    (let ((layouts (deref (field-pointer signatures 'layouts))))
      (cond
        ((< 0 (native_source_package_kind context form))
         (if (= (native_apply_package_form context form (field-pointer context 'package_state)) 1) 1
             (native_unit_fail result 4)))
        ((= (native_packed_layout_form_p layouts form) 1)
         (if (= (native_register_packed_layout layouts form) 1) 1
             (native_unit_fail result 1)))
        ((= (native_layout_form_p layouts form) 1)
         (if (= (native_register_layout layouts form) 1) 1
             (native_unit_fail result 1)))
        ((= (native_import_form_p signatures form) 1)
         (if (= (native_parse_import signatures form) 0)
             (native_unit_fail result 2)
             (if (= (native_latest_signature_data_name_free_p context) 1) 1
                 (native_unit_fail result 2))))
        ((= (native_import_data_form_p context form) 1)
         (if (= (native_parse_import_data context form) 1) 1
             (native_unit_fail result 2)))
        ((= (native_export_data_form_p context form) 1)
         (if (= (native_parse_export_data context form) 1) 1
             (native_unit_fail result 2)))
        (t
         (if (= (native_parse_signature signatures form) 0)
             (native_unit_fail result 3)
             (if (= (native_latest_signature_data_name_free_p context) 1) 1
                 (native_unit_fail result 3))))))))

(defun native_resolve_unit_form (context result)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result) (returns c-int))
  (let ((reader (deref (field-pointer (deref (field-pointer context 'parser)) 'environment))))
    (if (= (ptr-address reader) 0) 1
        (if (= (native_resolve_source_identities context reader) 1) 1
            (progn
              (store (field-pointer result 'form) (deref (field-pointer reader 'error)))
              0)))))

(defun native_collect_unit (context result)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (store (field-pointer result 'form) (parser_next parser))
    (while (if (= (deref (field-pointer result 'phase)) 0)
               (< 0 (deref (field-pointer result 'form))) nil)
      (if (= (native_resolve_unit_form context result) 1)
          (if (= (native_collect_form context result) 1)
              (store (field-pointer result 'form) (parser_next parser))
              (wrap-cast usize 0))
          (progn (native_unit_fail result 4) (wrap-cast usize 0))))
    (if (= (deref (field-pointer result 'phase)) 0)
        (let ((signatures (deref (field-pointer context 'signatures))))
          (let ((layouts (deref (field-pointer signatures 'layouts))))
            (if (= (deref (field-pointer parser 'error)) 0)
                (if (= (deref (field-pointer layouts 'error)) 0)
                    (if (if (< 0 (deref (field-pointer signatures 'signature_count)))
                            t (< 0 (deref (field-pointer context 'data_count))))
                        1 (native_unit_fail result 4))
                    (native_unit_fail result 4))
                (native_unit_fail result 4))))
        0)))

(defun native_unit_signature (context result)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result)
           (returns (ptr native_signature)))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (pointer+ (deref (field-pointer signatures 'signatures))
              (wrap-cast isize (deref (field-pointer result 'index))))))

(defun native_unit_function (context result)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result)
           (returns (ptr native_function)))
  (native_function_at (deref (field-pointer context 'functions))
                      (deref (field-pointer result 'index))))

(defun native_next_signature (result)
  (declare (type (ptr native_unit_result) result) (returns usize))
  (store (field-pointer result 'index)
         (wrap+ (deref (field-pointer result 'index)) 1)))

(defun native_unit_pending_p (result count)
  (declare (type (ptr native_unit_result) result) (type usize count)
           (returns c-int))
  (if (= (deref (field-pointer result 'phase)) 0)
      (if (< (deref (field-pointer result 'index)) count) 1 0) 0))

(defun native_predeclare_unit (context result count)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result) (type usize count)
           (returns c-int))
  (store (field-pointer result 'index) 0)
  (while (= (native_unit_pending_p result count) 1)
    (if (= (predeclare_scalar_form context
                                   (native_unit_signature context result)
                                   (native_unit_function context result)) 1)
        (progn (native_next_signature result) (wrap-cast c-int 1))
        (native_unit_fail result 5)))
  (if (= (deref (field-pointer result 'phase)) 0) 1 0))

(defun native_compile_unit_bodies (context result count)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result) (type usize count)
           (returns c-int))
  (store (field-pointer result 'index) 0)
  (store (field-pointer context 'prior_count) count)
  (while (= (native_unit_pending_p result count) 1)
    (let ((signature (native_unit_signature context result)))
      (if (= (deref (field-pointer signature 'imported)) 1)
          (progn (native_next_signature result) (wrap-cast c-int 1))
          (if (= (compile_scalar_form context signature
                                      (native_unit_function context result)) 1)
              (progn (native_next_signature result) (wrap-cast c-int 1))
              (native_unit_fail result 6)))))
  (if (= (deref (field-pointer result 'phase)) 0) 1 0))

(defun native_write_target_object (context code functions count fixups object)
  (declare (type (ptr native_compile_context) context) (type (ptr byte_buffer) code object)
           (type (ptr native_function) functions) (type usize count)
           (type (ptr native_fixup_arena) fixups) (returns c-int))
  (let ((target (deref (field-pointer context 'target))))
    (let ((data_count (deref (field-pointer context 'data_count))))
      (if (= data_count 0)
          (if (= (native_target_object_format target) 2)
              (write_coff64_calls (deref (field-pointer code 'data))
                                  (deref (field-pointer code 'length))
                                  functions count fixups object)
              (write_elf64_calls_target target (deref (field-pointer code 'data))
                                        (deref (field-pointer code 'length))
                                        functions count fixups object))
          (if (= (native_target_object_format target) 2)
              (write_coff64_calls_data
               (deref (field-pointer code 'data))
               (deref (field-pointer code 'length)) functions count fixups
               (deref (field-pointer context 'data_imports)) data_count
               (deref (field-pointer context 'data_fixups)) object)
              (write_elf64_calls_data_target
               target (deref (field-pointer code 'data))
               (deref (field-pointer code 'length)) functions count fixups
               (deref (field-pointer context 'data_imports)) data_count
               (deref (field-pointer context 'data_fixups)) object))))))

(defun native_finish_unit (context result count object)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_unit_result) result) (type usize count)
           (type (ptr byte_buffer) object) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (functions (deref (field-pointer context 'functions)))
        (fixups (deref (field-pointer context 'fixups))))
    (if (= (native_patch_unit_calls context count) 0)
        (native_unit_fail result 7)
        (if (= (native_write_target_object context code functions count fixups object) 1)
            1 (native_unit_fail result 8)))))

(include "driver_effects.lisp")
(include "driver_inline.lisp")

(defun native_compile_unit (context object result)
  (declare (type (ptr native_compile_context) context)
           (type (ptr byte_buffer) object)
           (type (ptr native_unit_result) result)
           (returns c-int) (c-export :c))
  (store (field-pointer result 'phase) 0)
  (store (field-pointer result 'form) 0)
  (store (field-pointer result 'index) 0)
  (if (= (native_target_valid_p (deref (field-pointer context 'target))) 0)
      (native_unit_fail result 10)
      (progn
      (store (field-pointer (source_layouts context) 'target)
             (deref (field-pointer context 'target)))
      (if (= (native_collect_unit context result) 0) 0
          (let ((signatures (deref (field-pointer context 'signatures))))
            (let ((count (deref (field-pointer signatures 'signature_count))))
              (if (= (native_predeclare_unit context result count) 0) 0
                  (if (= (native_certify_effects context result count) 0) 0
                      (if (= (native_prepare_inline_unit context result count) 0) 0
                          (if (= (native_compile_unit_bodies context result count) 0) 0
                              (native_finish_unit context result count object)))))))))))
