(in-package #:psl.backend.aarch64)

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
  (mov-immediate buffer 16 distance)
  (register-op buffer #xcb000000 register 29 16))

(defun root-store (buffer register distance)
  (root-address buffer 16 distance)
  (word buffer (logior #xf9000000 register (ash 16 5))))

(defun emit-roots-init (emitter)
  (let ((buffer (emitter-bytes emitter)))
    (mov-immediate buffer 9 2)
    (loop for register in (emitter-root-registers emitter) for index from 0
          do (store-slot buffer 9 register)
             (root-store buffer 9 (- (emitter-root-array emitter) (* 8 index))))))

(defun emit-roots-sync (emitter)
  (let ((buffer (emitter-bytes emitter)))
    (loop for register in (emitter-root-registers emitter) for index from 0
          do (load-slot buffer 9 register)
             (root-store buffer 9 (- (emitter-root-array emitter) (* 8 index))))))

(defun emit-root-call (emitter name)
  (push (make-relocation :offset (length (emitter-bytes emitter)) :name name :kind :call)
        (emitter-relocations emitter))
  (word (emitter-bytes emitter) #x94000000))

(defun emit-roots-enter (emitter)
  (emit-roots-sync emitter)
  (let ((buffer (emitter-bytes emitter)))
    (root-address buffer 0 (emitter-root-header emitter))
    (root-address buffer 1 (emitter-root-array emitter))
    (mov-immediate buffer 2 (length (emitter-root-registers emitter))))
  (emit-root-call emitter "psl_rt_push_roots"))

(defun emit-roots-leave (emitter)
  (root-address (emitter-bytes emitter) 0 (emitter-root-header emitter))
  (emit-root-call emitter "psl_rt_pop_roots"))
