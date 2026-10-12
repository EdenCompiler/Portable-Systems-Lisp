(include "root_frame.lisp")
;; Keep the fixed outgoing area, saved arguments, virtual words and scratch.
;; The root header follows the scratch word and its ascending vector follows it.
(defun win64_root_frame_slots (context)
 (declare (type (ptr native_compile_context) context) (returns usize))
 (let ((slots (native_root_frame_slots context)))
  (if (= (deref (field-pointer (deref (field-pointer context 'lir)) 'root_count)) 0) slots
   (if (= slots 0) 0 (if (= slots (wrap- (wrap-cast usize 0) 1)) 0 (wrap+ slots 1))))))
(defun win64_root_header_offset (context)
 (declare (type (ptr native_compile_context) context) (returns usize))
 (win64_local_offset (deref (field-pointer context 'backend_outgoing_size))
  (wrap+ (deref (field-pointer (deref (field-pointer context 'lir)) 'value_count)) 2)))
(defun win64_root_shadow_offset (context index)
 (declare (type (ptr native_compile_context) context) (type usize index) (returns usize))
 (wrap+ (win64_root_header_offset context) (wrap+ 32 (wrap* index 8))))
(defun win64_root_store_shadow (context)
 (declare (type (ptr native_compile_context) context) (returns c-int))
 (win64_frame_access (deref (field-pointer context 'code)) #x858948
  (win64_root_shadow_offset context (deref (field-pointer context 'root_scan_count)))))
(defun win64_root_copy_value (context initialize)
  (declare (type (ptr native_compile_context) context) (type c-int initialize) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (arena (deref (field-pointer context 'lir)))
        (index (deref (field-pointer context 'root_cursor))))
    (if (= (if (= initialize 1) (x86_load_immediate code 2)
               (win64_lir_load context index)) 0) 0
        (if (= (if (= initialize 1)
                   (win64_store_local code (deref (field-pointer context 'backend_outgoing_size)) index (deref (field-pointer arena 'value_count)))
                   (wrap-cast c-int 1)) 0) 0
            (win64_root_store_shadow context)))))

(defun win64_root_copy_values (context initialize)
  (declare (type (ptr native_compile_context) context) (type c-int initialize) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (store (field-pointer context 'root_cursor) 1)
    (store (field-pointer context 'root_scan_count) 0)
    (store (field-pointer context 'root_flags) 0)
    (while (if (= (deref (field-pointer context 'root_flags)) 0)
               (< (deref (field-pointer context 'root_cursor)) (wrap+ (deref (field-pointer arena 'value_count)) 1)) nil)
      (let ((type (ir_type_at (deref (field-pointer arena 'types)) (deref (field-pointer context 'root_cursor)))))
        (if (= (native_root_value_p type) 1)
            (if (= (win64_root_copy_value context initialize) 0)
                (store (field-pointer context 'root_flags) 1)
                (progn (store (field-pointer context 'root_scan_count) (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
                       (wrap-cast u32 0))) (wrap-cast u32 0)))
      (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
    (if (= (deref (field-pointer context 'root_flags)) 0) 1 0)))

(defun win64_root_copy_parameter (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((location (win64_lir_parameter_location context (wrap+ index 1))))
    (if (= (win64_lir_load_abi_parameter context location) 0) 0 (win64_root_store_shadow context))))

(defun win64_root_copy_parameters (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  ;; COPY-VALUES left the shadow cursor after its managed virtual words.
  (store (field-pointer context 'root_cursor) 0)
  (while (if (= (deref (field-pointer context 'root_flags)) 0)
             (< (deref (field-pointer context 'root_cursor)) (deref (field-pointer context 'current_arity))) nil)
    (let ((index (deref (field-pointer context 'root_cursor))))
      (if (= (scalar_signature_parameter_code context (deref (field-pointer context 'current_signature)) index) 15)
          (if (= (win64_root_copy_parameter context index) 0)
              (store (field-pointer context 'root_flags) 1)
              (progn (store (field-pointer context 'root_scan_count) (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
                     (wrap-cast u32 0))) (wrap-cast u32 0)))
    (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
  (if (= (deref (field-pointer context 'root_flags)) 0) 1 0))

(defun win64_root_initialize (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (if (= (win64_root_copy_values context 1) 0) 0
      (win64_root_copy_parameters context)))

(defun win64_root_call (context target)
  (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
  (store (field-pointer (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1)) 'referenced) 1)
  (emit_deferred_call (deref (field-pointer context 'code)) (deref (field-pointer context 'fixups)) target 0))

(defun win64_root_enter (context target)
 (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
 (let ((code (deref (field-pointer context 'code))))
  (if (= (win64_frame_access code #x8d8d48 (win64_root_header_offset context)) 0) 0
   (if (= (win64_frame_access code #x958d48 (win64_root_shadow_offset context 0)) 0) 0
    (if (= (room_for code 10) 0) 0
     (progn
      (emit_integer code #xb849 2)
      (emit_integer code (wrap-cast u64 (deref (field-pointer (deref (field-pointer context 'lir)) 'root_count))) 8)
      (win64_root_call context target)))))))
(defun win64_root_leave (context target)
 (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
 (if (= (win64_frame_access (deref (field-pointer context 'code)) #x8d8d48 (win64_root_header_offset context)) 0) 0
  (win64_root_call context target)))
(defun win64_root_control (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind))))
    (cond ((= kind 110) (win64_root_initialize context))
          ((= kind 111) (win64_root_enter context (deref (field-pointer op 'target))))
          ((= kind 112) 1)
          ((= kind 113) (win64_root_leave context (deref (field-pointer op 'target))))
          (t 0))))

(defun win64_root_publish_result (context op)
 (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op) (returns c-int))
 (if (= (deref (field-pointer (deref (field-pointer context 'lir)) 'root_count)) 0) 1
  (if (= (deref (field-pointer op 'scalar_code)) 15)
   (progn
    (native_root_shadow_index context (deref (field-pointer op 'destination)))
    (win64_root_store_shadow context)) 1)))
