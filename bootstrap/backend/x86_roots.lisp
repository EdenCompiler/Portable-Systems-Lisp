(include "root_frame.lisp")
;; SysV root storage lies below original local slots. Only RAX is needed for
;; slot initialization/synchronization; incoming arguments are already saved.
(defun x86_root_header_displacement (context)
  (declare (type (ptr native_compile_context) context) (returns u64))
  (x86_local_displacement (native_root_frame_slots context)))

(defun x86_root_shadow_displacement (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns u64))
  (wrap+ (x86_root_header_displacement context) (wrap+ 32 (wrap* (wrap-cast u64 index) 8))))

(defun x86_root_memory (code opcode displacement)
  (declare (type (ptr byte_buffer) code) (type u64 opcode displacement) (returns c-int))
  (if (= (room_for code 7) 0) 0
      (if (= (emit_integer code opcode 3) 0) 0 (emit_integer code displacement 4))))

(defun x86_root_store_shadow (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (x86_root_memory (deref (field-pointer context 'code)) #x858948
   (x86_root_shadow_displacement context (deref (field-pointer context 'root_scan_count)))))

(defun x86_root_copy_value (context initialize)
  (declare (type (ptr native_compile_context) context) (type c-int initialize) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (arena (deref (field-pointer context 'lir)))
        (index (deref (field-pointer context 'root_cursor))))
    (if (= (if (= initialize 1) (x86_load_immediate code 2)
               (x86_lir_load context index)) 0) 0
        (if (= (if (= initialize 1)
                   (x86_store_local code index (deref (field-pointer arena 'value_count)))
                   (wrap-cast c-int 1)) 0) 0
            (x86_root_store_shadow context)))))

(defun x86_root_copy_values (context initialize)
  (declare (type (ptr native_compile_context) context) (type c-int initialize) (returns c-int))
  (let ((arena (deref (field-pointer context 'lir))))
    (store (field-pointer context 'root_cursor) 1)
    (store (field-pointer context 'root_scan_count) 0)
    (store (field-pointer context 'root_flags) 0)
    (while (if (= (deref (field-pointer context 'root_flags)) 0)
               (< (deref (field-pointer context 'root_cursor)) (wrap+ (deref (field-pointer arena 'value_count)) 1)) nil)
      (let ((type (ir_type_at (deref (field-pointer arena 'types)) (deref (field-pointer context 'root_cursor)))))
        (if (= (native_root_value_p type) 1)
            (if (= (x86_root_copy_value context initialize) 0)
                (store (field-pointer context 'root_flags) 1)
                (progn (store (field-pointer context 'root_scan_count) (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
                       (wrap-cast u32 0))) (wrap-cast u32 0)))
      (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
    (if (= (deref (field-pointer context 'root_flags)) 0) 1 0)))

(defun x86_root_copy_parameter (context index)
  (declare (type (ptr native_compile_context) context) (type usize index) (returns c-int))
  (let ((location (x86_lir_param_location context (deref (field-pointer context 'current_signature)) index 0 0 0 0)))
    (if (= (x86_lir_load_abi_parameter context location) 0) 0 (x86_root_store_shadow context))))

(defun x86_root_copy_parameters (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  ;; COPY-VALUES left the shadow cursor after its managed virtual words.
  (store (field-pointer context 'root_cursor) 0)
  (while (if (= (deref (field-pointer context 'root_flags)) 0)
             (< (deref (field-pointer context 'root_cursor)) (deref (field-pointer context 'current_arity))) nil)
    (let ((index (deref (field-pointer context 'root_cursor))))
      (if (= (scalar_signature_parameter_code context (deref (field-pointer context 'current_signature)) index) 15)
          (if (= (x86_root_copy_parameter context index) 0)
              (store (field-pointer context 'root_flags) 1)
              (progn (store (field-pointer context 'root_scan_count) (wrap+ (deref (field-pointer context 'root_scan_count)) 1))
                     (wrap-cast u32 0))) (wrap-cast u32 0)))
    (store (field-pointer context 'root_cursor) (wrap+ (deref (field-pointer context 'root_cursor)) 1)))
  (if (= (deref (field-pointer context 'root_flags)) 0) 1 0))

(defun x86_root_initialize (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (if (= (x86_root_copy_values context 1) 0) 0
      (x86_root_copy_parameters context)))

(defun x86_root_call (context target)
  (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
  (store (field-pointer (native_function_at (deref (field-pointer context 'functions)) (wrap- target 1)) 'referenced) 1)
  (emit_deferred_call (deref (field-pointer context 'code)) (deref (field-pointer context 'fixups)) target 0))

(defun x86_root_enter (context target)
  (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
  (let ((code (deref (field-pointer context 'code))))
    (if (= (x86_root_memory code #xbd8d48 (x86_root_header_displacement context)) 0) 0
        (if (= (x86_root_memory code #xb58d48 (x86_root_shadow_displacement context 0)) 0) 0
            (if (= (room_for code 10) 0) 0
                (progn
                  (emit_integer code #xba48 2)
                  (emit_integer code (wrap-cast u64 (deref (field-pointer (deref (field-pointer context 'lir)) 'root_count))) 8)
                  (x86_root_call context target)))))))

(defun x86_root_leave (context target)
  (declare (type (ptr native_compile_context) context) (type usize target) (returns c-int))
  (if (= (x86_root_memory (deref (field-pointer context 'code)) #xbd8d48 (x86_root_header_displacement context)) 0) 0
      (x86_root_call context target)))

(defun x86_root_control (context op)
  (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op) (returns c-int))
  (let ((kind (deref (field-pointer op 'kind))))
    (cond ((= kind 110) (x86_root_initialize context))
          ((= kind 111) (x86_root_enter context (deref (field-pointer op 'target))))
          ((= kind 112) 1)
          ((= kind 113) (x86_root_leave context (deref (field-pointer op 'target))))
          (t 0))))

(defun x86_root_publish_result (context op)
 (declare (type (ptr native_compile_context) context) (type (ptr native_lir_instruction) op) (returns c-int))
 (if (= (deref (field-pointer (deref (field-pointer context 'lir)) 'root_count)) 0) 1
  (if (= (deref (field-pointer op 'scalar_code)) 15)
   (progn
    (native_root_shadow_index context (deref (field-pointer op 'destination)))
    (x86_root_store_shadow context)) 1)))
