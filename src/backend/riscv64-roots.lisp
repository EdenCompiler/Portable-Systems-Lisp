(in-package #:psl.backend.riscv64)

(defun configure-root-frame (emitter function frame-size)
  (let ((roots (lir-function-root-registers function)))
    (if roots
        (progn
          (unless (= (backend-contract-pointer-bits (emitter-contract emitter)) 64)
            (fail "hosted root ABI v1 requires a 64-bit target"))
          (setf (emitter-root-registers emitter) roots
                (emitter-root-header emitter) (+ frame-size 32)
                (emitter-root-array emitter) (+ frame-size 32 (* 8 (length roots))))
          (* 16 (ceiling (emitter-root-array emitter) 16)))
        frame-size)))

(defun root-address (buffer register distance)
  (load-immediate buffer 7 distance)
  (r-type buffer #x33 register 8 7 0 32))

(defun root-store (buffer register distance)
  (root-address buffer 7 distance)
  (s-type buffer #x23 7 register 3 0))

(defun emit-roots-init (emitter)
  (let ((buffer (emitter-bytes emitter)))
    (load-immediate buffer 5 2)
    (loop for register in (emitter-root-registers emitter) for index from 0
          do (store-slot buffer 5 register)
             (root-store buffer 5 (- (emitter-root-array emitter) (* 8 index))))))

(defun emit-roots-sync (emitter)
  (let ((buffer (emitter-bytes emitter)))
    (loop for register in (emitter-root-registers emitter) for index from 0
          do (load-slot buffer 5 register)
             (root-store buffer 5 (- (emitter-root-array emitter) (* 8 index))))))

(defun emit-root-call (emitter name)
  (push (make-relocation :offset (length (emitter-bytes emitter)) :name name :kind :call)
        (emitter-relocations emitter))
  (word (emitter-bytes emitter) #x00000097)
  (i-type (emitter-bytes emitter) #x67 1 1 0 0))

(defun emit-roots-enter (emitter)
  (emit-roots-sync emitter)
  (let ((buffer (emitter-bytes emitter)))
    (root-address buffer 10 (emitter-root-header emitter))
    (root-address buffer 11 (emitter-root-array emitter))
    (load-immediate buffer 12 (length (emitter-root-registers emitter))))
  (emit-root-call emitter "psl_rt_push_roots"))

(defun emit-roots-leave (emitter)
  (root-address (emitter-bytes emitter) 10 (emitter-root-header emitter))
  (emit-root-call emitter "psl_rt_pop_roots"))
