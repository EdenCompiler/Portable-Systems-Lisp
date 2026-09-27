(include "../binary.lisp")

;; A64 words are emitted directly in little-endian order. X9/X10 hold
;; expression operands; X16/X17 are addressing scratch registers.
(defun a64_word (code bits)
  (declare (type (ptr byte_buffer) code) (type u64 bits) (returns c-int))
  (emit_integer code bits 4))

(defun a64_register_op (code base destination left right)
  (declare (type (ptr byte_buffer) code) (type u64 base destination left right) (returns c-int))
  (a64_word code (wrap+ base (wrap+ destination (wrap+ (wrap* left 32) (wrap* right 65536))))))

(defun a64_immediate_halves (code register value half)
  (declare (type (ptr byte_buffer) code) (type u64 register value half) (returns c-int))
  (if (= half 4) 1
      (let ((piece (bits-and (shr64 value (wrap* half 16)) 65535)))
        (if (= piece 0) (a64_immediate_halves code register value (wrap+ half 1))
            (if (= (a64_word code (wrap+ #xf2800000
                     (wrap+ register (wrap+ (wrap* half #x200000) (wrap* piece 32))))) 0) 0
                (a64_immediate_halves code register value (wrap+ half 1)))))))

(defun a64_immediate (code register value)
  (declare (type (ptr byte_buffer) code) (type u64 register value) (returns c-int))
  (if (= (a64_word code (wrap+ #xd2800000 (wrap+ register (wrap* (bits-and value 65535) 32)))) 0) 0
      (a64_immediate_halves code register value 1)))

(defun a64_normalize (code register scalar_code)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type u32 scalar_code) (returns c-int))
  (let ((bits (scalar_type_bits scalar_code)))
    (if (= bits 64) 1
        (a64_word code (wrap+ (if (= (scalar_type_signed_p scalar_code) 1) #x93400000 #xd3400000)
                       (wrap+ (wrap* register 33) (wrap* (wrap-cast u64 (wrap- bits 1)) 1024)))))))

(defun a64_memory_opcode (width signed storing)
  (declare (type usize width) (type c-int signed storing) (returns u64))
  (cond
    ((= width 1) (if (= storing 1) #x39000000 (if (= signed 1) #x39800000 #x39400000)))
    ((= width 2) (if (= storing 1) #x79000000 (if (= signed 1) #x79800000 #x79400000)))
    ((= width 4) (if (= storing 1) #xb9000000 (if (= signed 1) #xb9800000 #xb9400000)))
    ((= width 8) (if (= storing 1) #xf9000000 #xf9400000))
    (t 0)))

(defun a64_memory (code width signed storing register address)
  (declare (type (ptr byte_buffer) code) (type usize width) (type c-int signed storing)
           (type u64 register address) (returns c-int))
  (let ((base (a64_memory_opcode width signed storing)))
    (if (= base 0) 0 (a64_word code (wrap+ base (wrap+ register (wrap* address 32)))))))
