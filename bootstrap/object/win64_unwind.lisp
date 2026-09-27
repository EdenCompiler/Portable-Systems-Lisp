(include "../binary.lisp")

;; This describes the native backend's push RBP / allocate / set RBP prologue.
;; Entries are in reverse execution order. The frame pointer equals body RSP.
(defun win64_unwind_slots (frame)
  (declare (type usize frame) (returns usize))
  (cond ((< 524280 frame) 5) ((< 128 frame) 4) (t 3)))

(defun win64_unwind_bytes (frame)
  (declare (type usize frame) (returns usize))
  (wrap+ 4 (wrap* 2 (bits-and (wrap+ (win64_unwind_slots frame) 1) (wrap- 0 2)))))

(defun win64_unwind_allocation (output frame offset)
  (declare (type (ptr byte_buffer) output) (type usize frame offset) (returns c-int))
  (emit_byte output (wrap-cast u8 offset))
  (cond
    ((< 524280 frame)
     (progn (emit_byte output #x11) (emit_integer output (wrap-cast u64 frame) 4)))
    ((< 128 frame)
     (progn (emit_byte output 1) (emit_integer output (shr64 (wrap-cast u64 frame) 3) 2)))
    (t (emit_byte output (wrap-cast u8 (wrap+ 2 (wrap* (wrap- (shr64 (wrap-cast u64 frame) 3) 1) 16)))))))

(defun win64_write_unwind (output frame prologue)
  (declare (type (ptr byte_buffer) output) (type usize frame prologue)
           (returns c-int) (c-export :c))
  (if (= frame 0) 0
      (if (< 2147483584 frame) 0
          (if (= (bits-and frame 15) 0)
              (if (= prologue (if (< frame 4096) (wrap-cast usize 11) (wrap-cast usize 67)))
                  (if (= (room_for output (win64_unwind_bytes frame)) 0) 0
                      (progn
                        (emit_byte output 1) ; version 1, no handler
                        (emit_byte output (wrap-cast u8 prologue))
                        (emit_byte output (wrap-cast u8 (win64_unwind_slots frame)))
                        (emit_byte output 5) ; RBP, frame offset 0
                        (emit_byte output (wrap-cast u8 prologue))
                        (emit_byte output 3) ; UWOP_SET_FPREG
                        (win64_unwind_allocation output frame (wrap- prologue 3))
                        (emit_integer output #x5001 2) ; UWOP_PUSH_NONVOL RBP
                        (if (= (bits-and (win64_unwind_slots frame) 1) 1)
                            (emit_integer output 0 2) (wrap-cast c-int 1))))
                  0)
              0))))
