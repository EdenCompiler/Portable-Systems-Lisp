;; Size output storage from the source-unit capacity. This covers longer fixed
;; instruction sequences and ELF symbol/relocation overhead without a core-size
;; ceiling. Storage preparation checks the combined product and additive term.
(defun native_data_capacity (capacity)
  (declare (type usize capacity) (returns usize))
  (wrap+ capacity 2048))

(defun native_code_capacity (capacity)
  (declare (type usize capacity) (returns usize))
  (wrap+ 1048576 (wrap* capacity 16)))

(defun native_object_capacity (capacity)
  (declare (type usize capacity) (returns usize))
  (wrap+ (native_code_capacity capacity) (wrap+ 1024 (wrap* capacity 64))))

(defun native_output_counts_fit (capacity)
  (declare (type usize capacity) (returns c-int))
  (if (= (native_count_product_fits capacity 80) 0) 0
      (let ((bytes (wrap* capacity 80)))
        (if (< bytes (wrap+ bytes 1049600)) 1 0))))
