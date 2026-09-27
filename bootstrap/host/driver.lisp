(include "storage.lisp")
(include "initialize.lisp")

;; Requires a zeroed driver with a live owned source. On failure, partial
;; allocations remain owned by DRIVER until native_release_driver is called.
;; A prepared driver must be released before preparing it again.
(defun native_prepare_driver (driver)
  (declare (type (ptr native_driver) driver) (returns c-int) (c-export :c))
  (let ((capacity (wrap+ (deref (field-pointer driver 'length)) 1))
        (storage (field-pointer driver 'storage)))
    (if (= (ptr-address (deref (field-pointer driver 'source))) 0) 0
        (if (= capacity 0) 0
            (if (= (native_count_product_fits capacity 6) 0) 0
                (if (= (native_allocate_frontend storage capacity) 0) 0
                    (if (= (native_allocate_ir storage capacity) 0) 0
                        (if (= (native_allocate_output storage capacity) 0) 0
                            (native_initialize_driver driver capacity)))))))))
