;; Hosted IR capture ownership and retry policy.
(defun compiler_ir_buffer_capacity (state)
  (declare (type (ptr native_compiler_state) state) (returns usize))
  (let ((length (deref (field-pointer
                         (field-pointer state 'driver)
                         'length)))
        (maximum (wrap-cast usize -1)))
    (let ((limit (wrap-cast usize
                   (shr64 (wrap-cast u64 (wrap- maximum 4096)) 6))))
      (if (< limit length) 0
          (wrap+ (wrap* length 64) 4096)))))

(defun compiler_ir_reset_request (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((output (field-pointer state 'ir_output))
        (dump (field-pointer state 'ir_dump)))
    (store (field-pointer output 'length) 0)
    (store (field-pointer dump 'output) output)
    (store (field-pointer dump 'stages)
           (deref (field-pointer (field-pointer state 'options) 'dump_stages)))
    (store (field-pointer dump 'required) 0)
    (store (field-pointer dump 'error) 0)
    (store (field-pointer dump 'cursor) 0)
    (store (field-pointer dump 'writing) 0)
    (store (field-pointer (field-pointer (field-pointer state 'driver) 'context)
                          'ir_dump) dump)
    1))

(defun compiler_resize_ir_dump (state capacity)
  (declare (type (ptr native_compiler_state) state) (type usize capacity)
           (returns c-int))
  (if (= capacity 0) 0
      (let ((memory (ptr-cast (ptr u8) (ffi:call calloc capacity 1))))
        (if (= (ptr-address memory) 0) 0
            (let ((output (field-pointer state 'ir_output)))
              (ffi:call free (ptr-cast (ptr void) (deref (field-pointer output 'data))))
              (store (field-pointer output 'data) memory)
              (store (field-pointer output 'capacity) capacity)
              (compiler_ir_reset_request state))))))

(defun compiler_setup_ir_dump (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (if (= (deref (field-pointer (field-pointer state 'options) 'dump_stages)) 0)
      (progn
        (store (field-pointer (field-pointer (field-pointer state 'driver) 'context)
                              'ir_dump) (ptr-from-address (ptr native_ir_dump) 0))
        1)
      (if (= (ptr-address (deref (field-pointer (field-pointer state 'ir_output) 'data))) 0)
          (compiler_resize_ir_dump state (compiler_ir_buffer_capacity state))
          (compiler_ir_reset_request state))))

(defun compiler_configure_driver (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((context (field-pointer (field-pointer state 'driver) 'context)))
    (store (field-pointer context 'optimization) (deref (field-pointer state 'optimization)))
    (store (field-pointer context 'target) (deref (field-pointer state 'target)))
    (store (field-pointer context 'profile) (deref (field-pointer state 'profile)))
    (compiler_setup_ir_dump state)))

(defun compiler_grow_ir_dump (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((capacity (deref (field-pointer (field-pointer state 'ir_output) 'capacity)))
        (required (deref (field-pointer (field-pointer state 'ir_dump) 'required)))
        (maximum (wrap-cast usize -1)))
    (if (< capacity required)
        (let ((grown (if (< (wrap- maximum capacity) capacity) maximum
                         (wrap+ capacity capacity))))
          (compiler_resize_ir_dump state (if (< grown required) required grown)))
        0)))

(defun compiler_reprepare_driver (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((driver (field-pointer state 'driver)))
    (let ((source (deref (field-pointer driver 'source)))
          (length (deref (field-pointer driver 'length))))
      ;; Transfer the source out while releasing all per-attempt arenas.
      (store (field-pointer driver 'source) (ptr-from-address (ptr u8) 0))
      (store (field-pointer driver 'length) 0)
      (ffi:call native_release_driver driver)
      (store (field-pointer driver 'source) source)
      (store (field-pointer driver 'length) length)
      (ffi:call native_prepare_driver_capacity driver
                (deref (field-pointer state 'driver_capacity))))))

(defun compiler_grow_driver_capacity (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((capacity (deref (field-pointer state 'driver_capacity)))
        (maximum (wrap-cast usize -1)))
    (if (< (wrap- maximum capacity) capacity) 0
        (let ((grown (wrap+ capacity capacity)))
          (if (< grown capacity) 0
              (if (= grown capacity) 0
                  (progn (store (field-pointer state 'driver_capacity) grown) 1)))))))

(defun compiler_retry_driver_capacity (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (if (= (compiler_grow_driver_capacity state) 0) 0
      (if (= (compiler_reprepare_driver state) 0) 0
          (if (= (compiler_configure_driver state) 0) 0 1))))

(defun compiler_compile_with_growth (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((driver (field-pointer state 'driver)) (result (field-pointer state 'result)))
    (store (field-pointer result 'phase) 0)
    (store (field-pointer result 'form) 0)
    (store (field-pointer result 'index) 0)
    (if (= (ffi:call native_compile_unit (field-pointer driver 'context)
                       (field-pointer driver 'object) result) 1) 1
        (if (= (deref (field-pointer (field-pointer state 'ir_dump) 'error)) 2)
            (if (= (compiler_grow_ir_dump state) 0)
                (progn (compiler_path_error 22 (ptr-from-address (ptr u8) 0)) -1)
                (if (= (compiler_reprepare_driver state) 0)
                    (progn (compiler_path_error 2 (ptr-from-address (ptr u8) 0)) -1)
                    (if (= (compiler_configure_driver state) 0)
                        (progn (compiler_path_error 22 (ptr-from-address (ptr u8) 0)) -1)
                        (compiler_compile_with_growth state))))
            (if (= (deref (field-pointer
                           (field-pointer (field-pointer driver 'context) 'macro_call)
                           'error)) 3)
                (if (= (compiler_retry_driver_capacity state) 0)
                    (progn (compiler_path_error 2 (ptr-from-address (ptr u8) 0)) -1)
                    (compiler_compile_with_growth state))
                0)))))

(defun compiler_release_ir_dump (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((memory (deref (field-pointer (field-pointer state 'ir_output) 'data))))
    (if (< 0 (ptr-address memory))
        (progn (ffi:call free (ptr-cast (ptr void) memory)) 0) 0)
    (store (field-pointer (field-pointer state 'ir_output) 'data)
           (ptr-from-address (ptr u8) 0))
    (store (field-pointer
             (field-pointer (field-pointer state 'driver) 'context) 'ir_dump)
           (ptr-from-address (ptr native_ir_dump) 0))
    1))

(defun compiler_flush_ir_dump (state)
  (declare (type (ptr native_compiler_state) state) (returns c-int))
  (let ((stages (deref (field-pointer
                         (field-pointer state 'options) 'dump_stages)))
        (output (field-pointer state 'ir_output)))
    (if (= stages 0) 1
        (if (= (ffi:call native_host_write_ir
                         (deref (field-pointer output 'data))
                         (deref (field-pointer output 'length))) 1)
            1
            (progn
              (ffi:call native_host_report_error 21
                (ptr-from-address (ptr u8) 0) 0 0)
              0)))))
