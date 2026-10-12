;; Runtime ABI v1 roots occupy a 32-byte header and a contiguous word vector.
;; Extra slots affect frame sizing only; original virtual-register offsets stay.
(defun native_root_frame_slots (context)
  (declare (type (ptr native_compile_context) context) (returns usize))
  (let ((arena (deref (field-pointer context 'lir))))
    (let ((values (deref (field-pointer arena 'value_count)))
          (roots (deref (field-pointer arena 'root_count))))
      (if (= roots 0) values
          (if (< (wrap- (wrap- (wrap- (wrap-cast usize 0) 1) values) 4) roots) 0
              (wrap+ values (wrap+ roots 4)))))))
