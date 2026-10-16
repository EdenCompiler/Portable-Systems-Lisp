(include "storage.lisp")
(include "initialize.lisp")

;; Capacity is the common node/record arena size and must include the complete
;; source parse plus any build-host macro expansion growth.
(defun native_prepare_driver_capacity (driver capacity)
  (declare (type (ptr native_driver) driver) (type usize capacity)
           (returns c-int) (c-export :c))
  (let ((minimum (wrap+ (deref (field-pointer driver 'length)) 1))
        (storage (field-pointer driver 'storage)))
    (if (= (ptr-address (deref (field-pointer driver 'source))) 0) 0
        (if (= minimum 0) 0
            (if (< capacity minimum) 0
            (if (= (native_output_counts_fit capacity) 0) 0
            (if (= (native_environment_counts_fit capacity) 0) 0
                (if (= (native_closure_counts_fit capacity) 0) 0
                    (if (= (native_allocate_frontend storage capacity) 0) 0
                    (if (= (native_allocate_ir storage capacity) 0) 0
                            (if (= (native_allocate_output storage capacity) 0) 0
                                    (if (= (native_allocate_environment storage capacity) 0) 0
                                        (if (= (native_allocate_macros storage) 0) 0
                                        (native_initialize_driver driver capacity))))))))))))))

;; Keep the library API's historical source-sized default. Hosted controllers
;; may explicitly choose a larger retry arena after a latched macro-capacity
;; failure; caller-owned fixed arenas remain unchanged.
(defun native_prepare_driver (driver)
  (declare (type (ptr native_driver) driver) (returns c-int) (c-export :c))
  (let ((capacity (wrap+ (deref (field-pointer driver 'length)) 1)))
    (if (= capacity 0) 0
        (native_prepare_driver_capacity driver capacity))))
