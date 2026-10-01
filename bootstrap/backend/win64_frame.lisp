(include "../binary.lisp")

;; RBP equals the fixed body RSP. The frame contains outgoing shadow/stack
;; arguments, four saved incoming GP and FP registers, virtual registers, and a
;; scratch word. Body instructions never push, pop, or adjust RSP.
(defun win64_align_frame (bytes)
  (declare (type usize bytes) (returns usize))
  (bits-and (wrap+ bytes 15) (wrap- 0 16)))

(defun win64_outgoing_bytes (arity)
  (declare (type usize arity) (returns usize))
  (if (< 268435445 arity) 0
      (win64_align_frame (wrap+ 32 (wrap* 8 (if (< 4 arity) (wrap- arity 4) (wrap-cast usize 0)))))))

(defun win64_frame_bytes (values outgoing)
  (declare (type usize values outgoing) (returns usize) (c-export :c))
  (if (< 268435445 values) 0
      (if (< 2147483632 outgoing) 0
      (let ((bytes (win64_align_frame (wrap+ outgoing (wrap+ 72 (wrap* values 8))))))
            ;; Leave room for the incoming return address and stack parameters.
            (if (< 2147483584 bytes) 0 bytes)))))

(defun win64_frame_access (code opcode offset)
  (declare (type (ptr byte_buffer) code) (type u64 opcode)
           (type usize offset) (returns c-int))
  (if (< 2147483647 offset) 0
      (if (= (room_for code 7) 0) 0
          (progn (emit_integer code opcode 3)
                 (emit_integer code (wrap-cast u64 offset) 4)))))

(defun win64_local_offset (outgoing reference)
  (declare (type usize outgoing reference) (returns usize))
  (wrap+ outgoing (wrap+ 64 (wrap* (wrap- reference 1) 8))))

(defun win64_load_local (code outgoing reference values)
  (declare (type (ptr byte_buffer) code) (type usize outgoing reference values)
           (returns c-int) (c-export :c))
  (if (= reference 0) 0
      (if (< values reference) 0
          (win64_frame_access code #x858b48 (win64_local_offset outgoing reference)))))

(defun win64_store_local (code outgoing reference values)
  (declare (type (ptr byte_buffer) code) (type usize outgoing reference values)
           (returns c-int) (c-export :c))
  (if (= reference 0) 0
      (if (< values reference) 0
          (win64_frame_access code #x858948 (win64_local_offset outgoing reference)))))

(defun win64_load_parameter (code outgoing frame index)
  (declare (type (ptr byte_buffer) code) (type usize outgoing frame index)
           (returns c-int) (c-export :c))
  (if (= index 0) 0
      (if (< 268435445 index) 0
          (win64_frame_access code #x858b48
            (if (< 4 index) (wrap+ frame (wrap+ 48 (wrap* (wrap- index 5) 8)))
                (wrap+ outgoing (wrap* (wrap- index 1) 8)))))))

(defun win64_save_parameters (code outgoing)
  (declare (type (ptr byte_buffer) code) (type usize outgoing) (returns c-int))
  (if (= (win64_frame_access code #x8d8948 outgoing) 0) 0 ; RCX
      (if (= (win64_frame_access code #x958948 (wrap+ outgoing 8)) 0) 0 ; RDX
          (if (= (win64_frame_access code #x85894c (wrap+ outgoing 16)) 0) 0 ; R8
              (if (= (win64_frame_access code #x8d894c (wrap+ outgoing 24)) 0) 0 ; R9
                  1)))))

(defun win64_save_float_parameters (code outgoing index)
  (declare (type (ptr byte_buffer) code) (type usize outgoing index) (returns c-int))
  (if (= index 4) 1
      (if (= (room_for code 8) 0) 0
          (progn
            (emit_byte_unchecked code #x66)
            (emit_byte_unchecked code #x0f)
            (emit_byte_unchecked code #xd6)
            (emit_byte_unchecked code (wrap-cast u8 (wrap+ #x85 (wrap* index 8))))
            (emit_integer code (wrap-cast u64 (wrap+ outgoing (wrap+ 32 (wrap* index 8)))) 4)
            (win64_save_float_parameters code outgoing (wrap+ index 1))))))

(defun win64_return (code frame)
  (declare (type (ptr byte_buffer) code) (type usize frame)
           (returns c-int) (c-export :c))
  (if (= (room_for code 9) 0) 0
      (progn
        (emit_integer code #xa58d48 3) ; lea rsp, [rbp+frame]
        (emit_integer code (wrap-cast u64 frame) 4)
        (emit_integer code #xc35d 2)))) ; pop rbp; ret
