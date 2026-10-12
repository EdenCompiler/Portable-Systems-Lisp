;; Validate the original argument catalogue before scanning lazy parameters.
(defun native_root_parameters_p (context)
 (declare (type (ptr native_compile_context) context) (returns c-int))
 (let ((signatures (deref (field-pointer context 'signatures)))
       (signature (deref (field-pointer context 'current_signature))))
  (let ((count (deref (field-pointer signatures 'parameter_count)))
        (first (deref (field-pointer signature 'first_parameter)))
        (arity (deref (field-pointer signature 'arity))))
   (if (= (deref (field-pointer signatures 'error)) 0)
    (if (< (deref (field-pointer signatures 'parameter_capacity)) count) 0
     (if (< count first) 0
      (if (< (wrap- count first) arity) 0
       (if (= (deref (field-pointer context 'current_arity)) arity) 1 0)))) 0))))

;; Argument-chain catalogue entries do not occupy program-value slots.
(defun native_root_value_p (type)
 (declare (type (ptr native_ir_type) type) (returns c-int))
 (if (= (deref (field-pointer type 'scalar_code)) 15)
  (if (= (deref (field-pointer type 'kind)) 17) 0 1) 0))

;; Precise root catalogue: managed virtual words and saved source arguments.
;; Native SSA argument reads are lazy; original VALUE parameters need independent
;; shadow roots before any body call, even if their first read is in a branch.
(defun native_root_value_count (context)
  (declare (type (ptr native_compile_context) context) (returns usize))
  (let ((arena (deref (field-pointer context 'lir))))
    (store (field-pointer context 'root_cursor) 1)
    (store (field-pointer context 'root_scan_count) 0)
    (while (< (deref (field-pointer context 'root_cursor))
              (wrap+ (deref (field-pointer arena 'value_count)) 1))
      (let ((type (ir_type_at (deref (field-pointer arena 'types))
                             (deref (field-pointer context 'root_cursor)))))
        (if (= (native_root_value_p type) 1)
            (store (field-pointer context 'root_scan_count)
                   (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
            (wrap-cast usize 0)))
      (store (field-pointer context 'root_cursor)
             (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
    (deref (field-pointer context 'root_scan_count))))

(defun native_root_parameter_count (context)
  (declare (type (ptr native_compile_context) context) (returns usize))
  (store (field-pointer context 'root_cursor) 0)
  (store (field-pointer context 'root_scan_count) 0)
  (while (< (deref (field-pointer context 'root_cursor)) (deref (field-pointer context 'current_arity)))
    (if (= (scalar_signature_parameter_code context (deref (field-pointer context 'current_signature))
                                            (deref (field-pointer context 'root_cursor))) 15)
        (store (field-pointer context 'root_scan_count)
               (wrap+ (deref (field-pointer context 'root_scan_count)) 1)) (wrap-cast usize 0))
    (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
  (deref (field-pointer context 'root_scan_count)))

(defun native_root_collecting_call_p (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (store (field-pointer context 'root_cursor) 1)
    (store (field-pointer context 'root_flags) 0)
    (while (if (= (deref (field-pointer context 'root_flags)) 0)
               (< (deref (field-pointer context 'root_cursor)) (wrap+ (deref (field-pointer arena 'count)) 1)) nil)
      (let ((op (lir_instruction_at arena (deref (field-pointer context 'root_cursor)))))
        (if (= (deref (field-pointer op 'kind)) 7)
            (if (= (hir_call_allocation_free_p context (deref (field-pointer op 'target)) 1) 0)
                (store (field-pointer context 'root_flags) 1) (wrap-cast u32 0)) (wrap-cast u32 0)))
      (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
    (if (= (deref (field-pointer context 'root_flags)) 1) 1 0)))

(defun native_root_required_count (context)
  (declare (type (ptr native_compile_context) context) (returns usize))
  (if (= (native_root_collecting_call_p context) 0) 0
      (let ((values (native_root_value_count context)))
        (let ((arguments (native_root_parameter_count context)))
          (wrap+ values arguments)))))

(defun native_root_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (if (< kind 110) 0 (if (< 113 kind) 0 1)))

;; Shadow slots are published at every managed assignment. A sync boundary
;; needs no machine work because its vector already contains the latest words.
(defun native_root_shadow_index (context reference)
 (declare (type (ptr native_compile_context) context) (type usize reference) (returns usize))
 (let ((arena (deref (field-pointer context 'lir))))
  (store (field-pointer context 'root_cursor) 1)
  (store (field-pointer context 'root_scan_count) 0)
  (while (< (deref (field-pointer context 'root_cursor)) reference)
   (if (= (native_root_value_p (ir_type_at (deref (field-pointer arena 'types))
          (deref (field-pointer context 'root_cursor)))) 1)
    (store (field-pointer context 'root_scan_count) (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
    (wrap-cast usize 0))
   (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
  (deref (field-pointer context 'root_scan_count))))
