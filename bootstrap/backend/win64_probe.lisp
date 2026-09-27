(include "win64_frame.lisp")

;; Probe every crossed page using volatile registers while RSP still points
;; at the saved RBP. A fault before the final allocation can therefore unwind
;; as a partial prologue. No __chkstk or runtime module is required.
(defun win64_probe_loop (code loop_start)
  (declare (type (ptr byte_buffer) code) (type usize loop_start) (returns c-int))
  (emit_integer code #x00001000ea8149 7) ; sub r10, 4096
  (emit_integer code #x0002f641 4) ; test byte [r10], 0
  (emit_integer code #x00001000eb8149 7) ; sub r11, 4096
  (emit_byte code #xe9)
  (emit_integer code (wrap-cast u64 (wrap- loop_start (wrap+ (deref (field-pointer code 'length)) 4))) 4))

(defun win64_probe_pages (code frame)
  (declare (type (ptr byte_buffer) code) (type usize frame) (returns c-int))
  (if (< frame 4096) 1
      (if (= (room_for code 56) 0) 0
          (progn
            (emit_integer code #xe28949 3) ; mov r10, rsp
            (emit_integer code #xbb49 2) ; movabs r11, frame
            (emit_integer code (wrap-cast u64 frame) 8)
            (let ((loop_start (deref (field-pointer code 'length))))
              (emit_integer code #x00001000fb8149 7) ; cmp r11, 4096
              (emit_integer code #x820f 2) ; jb tail
              (emit_integer code 23 4)
              (win64_probe_loop code loop_start)
              (emit_integer code #xda294d 3) ; sub r10, r11
              (emit_integer code #x0002f641 4)))))) ; test byte [r10], 0

(defun win64_function_prologue (code frame outgoing)
  (declare (type (ptr byte_buffer) code) (type usize frame outgoing)
           (returns usize) (c-export :c))
  (if (= frame 0) 0
      (if (< frame outgoing) 0
          (if (< 2147483584 frame) 0
              (if (= (bits-and frame 15) 0)
                  (if (= (room_for code (if (< frame 4096) 39 (wrap-cast usize 95))) 0) 0
                      (progn
                        (emit_byte code #x55) ; push rbp
                        (win64_probe_pages code frame)
                        (emit_integer code #xec8148 3) ; sub rsp, frame
                        (emit_integer code (wrap-cast u64 frame) 4)
                        (emit_integer code #xe58948 3) ; mov rbp, rsp
                        (win64_save_parameters code outgoing)
                        (if (< frame 4096) (wrap-cast usize 11) (wrap-cast usize 67))))
                  0)))))
