(in-package #:psl.binary)

(defun byte-buffer ()
  (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))

(defun emit-byte (buffer value)
  (vector-push-extend (ldb (byte 8 0) value) buffer))

(defun emit-integer (buffer value count)
  (dotimes (i count) (emit-byte buffer (ash value (* -8 i)))))

(defun emit-bytes (buffer &rest bytes)
  (dolist (byte bytes) (emit-byte buffer byte)))

(defun patch-i32 (buffer offset value)
  (unless (<= (- (expt 2 31)) value (1- (expt 2 31)))
    (fail "32-bit displacement is out of range"))
  (dotimes (i 4)
    (setf (aref buffer (+ offset i)) (ldb (byte 8 (* 8 i)) value))))
