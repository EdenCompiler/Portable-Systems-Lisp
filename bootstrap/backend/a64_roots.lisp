(include "root_frame.lisp")
;; Preserve the original virtual slots; the root header is below them.
(defun a64_root_header_offset (context)
 (declare (type (ptr native_compile_context) context) (returns usize))
 (a64_local_offset (native_root_frame_slots context)))
(defun a64_root_shadow_offset (context index)
 (declare (type (ptr native_compile_context) context) (type usize index) (returns usize))
 (wrap- (a64_root_header_offset context) (wrap+ 32 (wrap* index 8))))
(defun a64_root_store_shadow (context)
 (declare (type (ptr native_compile_context) context) (returns c-int))
 (a64_store_frame (deref (field-pointer context 'code)) 9
  (a64_root_shadow_offset context (deref (field-pointer context 'root_scan_count)))))
(defun a64_root_address (context register offset)
 (declare (type (ptr native_compile_context) context) (type u64 register) (type usize offset) (returns c-int))
 (let ((code (deref (field-pointer context 'code))))
  (if (= (a64_frame_address code offset 1) 0) 0
   (a64_register_op code #xaa000000 register 31 16))))
(defun a64_root_copy_value (context initialize)
  (declare (type (ptr native_compile_context) context) (type c-int initialize) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (arena (deref (field-pointer context 'lir)))
        (index (deref (field-pointer context 'root_cursor))))
    (if (= (if (= initialize 1) (a64_immediate code 9 2)
               (a64_lir_load context 9 index)) 0) 0
        (if (= (if (= initialize 1)
                   (a64_store_frame code 9 (a64_local_offset index))
                   (wrap-cast c-int 1)) 0) 0
            (a64_root_store_shadow context)))))

(defun a64_root_copy_values (context initialize)
  (declare (type (ptr native_compile_context) context) (type c-int initialize) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (store (field-pointer context 'root_cursor) 1)
    (store (field-pointer context 'root_scan_count) 0)
    (store (field-pointer context 'root_flags) 0)
    (while (if (= (deref (field-pointer context 'root_flags)) 0)
               (< (deref (field-pointer context 'root_cursor)) (wrap+ (deref (field-pointer arena 'value_count)) 1)) nil)
      (let ((type (ir_type_at (deref (field-pointer arena 'types)) (deref (field-pointer context 'root_cursor)))))
        (if (= (native_root_value_p type) 1)
            (if (= (a64_root_copy_value context initialize) 0)
                (store (field-pointer context 'root_flags) 1)
                (progn (store (field-pointer context 'root_scan_count) (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
                       (wrap-cast u32 0))) (wrap-cast u32 0)))
      (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
    (if (= (deref (field-pointer context 'root_flags)) 0) 1 0)))

(defun a64_root_copy_parameter (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((location (a64_lir_param_location context (deref (field-pointer context 'current_signature)) index 0 0 0 0)))
    (if (= (a64_lir_load_abi_parameter context location) 0) 0 (a64_root_store_shadow context))))

(defun a64_root_copy_parameters (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  ;; COPY-VALUES left the shadow cursor after its managed virtual words.
  (store (field-pointer context 'root_cursor) 0)
  (while (if (= (deref (field-pointer context 'root_flags)) 0)
             (< (deref (field-pointer context 'root_cursor)) (deref (field-pointer context 'current_arity))) nil)
    (let ((index (deref (field-pointer context 'root_cursor))))
      (if (= (scalar_signature_parameter_code context (deref (field-pointer context 'current_signature)) index) 15)
          (if (= (a64_root_copy_parameter context index) 0)
              (store (field-pointer context 'root_flags) 1)
              (progn (store (field-pointer context 'root_scan_count) (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
                     (wrap-cast u32 0))) (wrap-cast u32 0)))
    (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
  (if (= (deref (field-pointer context 'root_flags)) 0) 1 0))

(defun a64_root_initialize (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (if (= (a64_root_copy_values context 1) 0) 0
      (a64_root_copy_parameters context)))

(defun a64_root_call (context target)
  (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
  (store (field-pointer (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1)) 'referenced) 1)
  (a64_deferred_call (deref (field-pointer context 'code)) (deref (field-pointer context 'fixups)) target))

(defun a64_root_enter (context target)
 (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
 (if (= (a64_root_address context 0 (a64_root_header_offset context)) 0) 0
  (if (= (a64_root_address context 1 (a64_root_shadow_offset context 0)) 0) 0
   (if (= (a64_immediate (deref (field-pointer context 'code)) 2
     (wrap-cast u64 (deref (field-pointer (deref (field-pointer context 'lir)) 'root_count)))) 0) 0
    (a64_root_call context target)))))
(defun a64_root_leave (context target)
 (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
 (if (= (a64_root_address context 0 (a64_root_header_offset context)) 0) 0
  (a64_root_call context target)))
(defun a64_root_control (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind))))
    (cond ((= kind 110) (a64_root_initialize context))
          ((= kind 111) (a64_root_enter context (deref (field-pointer op 'target))))
          ((= kind 112) 1)
          ((= kind 113) (a64_root_leave context (deref (field-pointer op 'target))))
          (t 0))))

(defun a64_root_publish_result (context op)
 (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op) (returns c-int))
 (if (= (deref (field-pointer (deref (field-pointer context 'lir)) 'root_count)) 0) 1
  (if (= (deref (field-pointer op 'scalar_code)) 15)
   (progn
    (native_root_shadow_index context (deref (field-pointer op 'destination)))
    (a64_root_store_shadow context)) 1)))
