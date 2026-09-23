(in-package #:psl.ir)

(defun integer-type-p (type)
  (member type '(:u8 :u16 :u32 :u64 :s8 :s16 :s32 :s64
                 :usize :isize)))

(defun float-type-p (type)
  (member type '(:f32 :f64)))

(defun signed-type-p (type)
  (member type '(:s8 :s16 :s32 :s64 :isize)))

(defun type-width (type pointer-bits)
  (case type
    ((:u8 :s8) 8)
    ((:u16 :s16) 16)
    ((:u32 :s32) 32)
    ((:u64 :s64) 64)
    ((:usize :isize) pointer-bits)
    (otherwise nil)))

(defun pointer-type-p (type)
  (and (consp type) (eq (first type) :ptr)))

(defun pointed-type (type)
  (second type))

(defun pointer-const-p (type)
  (third type))

(defun pointer-volatile-p (type)
  (fourth type))
