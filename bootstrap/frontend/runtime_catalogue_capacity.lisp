;; The hosted runtime catalogue reserves 28 signatures and 45 parameter
;; records. Driver capacity sizes both tables; parameter records set the floor.
(defun native_runtime_catalogue_signature_count ()
  (declare (returns usize)) 28)

(defun native_runtime_catalogue_parameter_count ()
  (declare (returns usize)) 45)

(defun native_runtime_catalogue_minimum_capacity ()
  (declare (returns usize) (c-export :c))
  (let ((signatures (native_runtime_catalogue_signature_count))
        (parameters (native_runtime_catalogue_parameter_count)))
    (if (< signatures parameters) parameters signatures)))
