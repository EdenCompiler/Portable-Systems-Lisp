(include "../binary.lisp")

;; RV64 instruction words. t0/t1 hold operands, t2 addresses stack slots,
;; t3/t4 handle scaling and byte-wise raw memory accesses. gp/tp are untouched.
(defun rv_word (code bits)
  (declare (type (ptr byte_buffer) code) (type u64 bits) (returns c-int))
  (emit_integer code bits 4))

(defun rv_r (code opcode destination left right funct3 funct7)
  (declare (type (ptr byte_buffer) code)
           (type u64 opcode destination left right funct3 funct7) (returns c-int))
  (rv_word code (wrap+ opcode (wrap+ (wrap* destination 128)
    (wrap+ (wrap* funct3 4096) (wrap+ (wrap* left 32768)
      (wrap+ (wrap* right 1048576) (wrap* funct7 33554432))))))))

(defun rv_i_word (opcode destination source funct3 immediate)
  (declare (type u64 opcode destination source funct3 immediate) (returns u64))
  (wrap+ opcode (wrap+ (wrap* destination 128) (wrap+ (wrap* funct3 4096)
    (wrap+ (wrap* source 32768) (wrap* (bits-and immediate 4095) 1048576))))))

(defun rv_i (code opcode destination source funct3 immediate)
  (declare (type (ptr byte_buffer) code) (type u64 opcode destination source funct3 immediate)
           (returns c-int))
  (rv_word code (rv_i_word opcode destination source funct3 immediate)))

(defun rv_s (code address value funct3 immediate)
  (declare (type (ptr byte_buffer) code) (type u64 address value funct3 immediate) (returns c-int))
  (let ((bits (bits-and immediate 4095)))
    (rv_word code (wrap+ #x23 (wrap+ (wrap* (bits-and bits 31) 128)
      (wrap+ (wrap* funct3 4096) (wrap+ (wrap* address 32768)
        (wrap+ (wrap* value 1048576) (wrap* (shr64 bits 5) 33554432)))))))))

(defun rv_move (code destination source)
  (declare (type (ptr byte_buffer) code) (type u64 destination source) (returns c-int))
  (rv_i code #x13 destination source 0 0))

(defun rv_immediate_bytes (code register value shift started)
  (declare (type (ptr byte_buffer) code) (type u64 register value shift)
           (type c-int started) (returns c-int))
  (let ((piece (bits-and (shr64 value shift) 255)))
    (if (if (= started 1) t (if (= piece 0) (= shift 0) t))
        (if (= started 1)
            (if (= (rv_i code #x13 register register 1 8) 0) 0
                (if (= (rv_i code #x13 register register 0 piece) 0) 0
                    (if (= shift 0) 1 (rv_immediate_bytes code register value (wrap- shift 8) 1))))
            (if (= (rv_i code #x13 register 0 0 piece) 0) 0
                (if (= shift 0) 1 (rv_immediate_bytes code register value (wrap- shift 8) 1))))
        (rv_immediate_bytes code register value (wrap- shift 8) 0))))

(defun rv_immediate (code register value)
  (declare (type (ptr byte_buffer) code) (type u64 register value) (returns c-int))
  (rv_immediate_bytes code register value 56 0))

(defun rv_normalize_width (code register bits signed)
  (declare (type (ptr byte_buffer) code) (type u64 register bits)
           (type c-int signed) (returns c-int))
  (if (= bits 64) 1
      (let ((shift (wrap- 64 bits)))
        (if (= (rv_i code #x13 register register 1 shift) 0) 0
            (rv_i code #x13 register register 5 (wrap+ shift (if (= signed 1) #x400 (wrap-cast u64 0))))))))

(defun rv_normalize (code register scalar_code)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type u32 scalar_code) (returns c-int))
  (rv_normalize_width code register (wrap-cast u64 (scalar_type_bits scalar_code))
                      (scalar_type_signed_p scalar_code)))

(defun rv_abi_normalize (code register scalar_code)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type u32 scalar_code) (returns c-int))
  ;; The psABI sign-extends 32-bit arguments/results even when unsigned.
  (if (= (scalar_type_bits scalar_code) 32) (rv_normalize_width code register 32 1) 1))
