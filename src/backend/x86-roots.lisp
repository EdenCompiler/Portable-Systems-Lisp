(in-package #:psl.backend.x86-64)

(defun configure-root-frame (emitter function)
  (let ((roots (lir-function-root-registers function)))
    (when roots
      (unless (= (backend-contract-pointer-bits (emitter-contract emitter)) 64)
        (fail "hosted root ABI v1 requires a 64-bit target"))
      (let ((slots (+ (lir-function-register-count function)
                      (if (emitter-return-buffer-slot emitter) 1 0))))
        (setf (emitter-root-registers emitter) roots
              (emitter-root-header emitter) (- (+ (* slots 16) 32))
              (emitter-root-array emitter) (- (+ (* slots 16) 32 (* 8 (length roots)))))))))

(defun emit-root-store (buffer displacement)
  (emit-bytes buffer #x48 #x89 #x85)
  (emit-integer buffer displacement 4))

(defun emit-frame-address (buffer register displacement)
  (emit-bytes buffer (if (< register 8) #x48 #x4c) #x8d
              (+ #x85 (* 8 (mod register 8))))
  (emit-integer buffer displacement 4))

(defun emit-root-immediate (buffer register number)
  (emit-bytes buffer (if (< register 8) #x48 #x49) (+ #xb8 (mod register 8)))
  (emit-integer buffer number 8))

(defun emit-roots-init (emitter)
  (let ((buffer (emitter-bytes emitter)))
    (emit-root-immediate buffer 0 2)
    (loop for register in (emitter-root-registers emitter)
          for index from 0
          do (emit-store-slot buffer 0 register)
             (emit-root-store buffer (+ (emitter-root-array emitter) (* 8 index))))))

(defun emit-roots-sync (emitter)
  (let ((buffer (emitter-bytes emitter)))
    (loop for register in (emitter-root-registers emitter)
          for index from 0
          do (emit-load-slot buffer 0 register)
             (emit-root-store buffer (+ (emitter-root-array emitter) (* 8 index))))))

(defun emit-root-call (emitter name)
  (let ((buffer (emitter-bytes emitter)))
    (emit-byte buffer #xe8)
    (push (make-relocation :offset (length buffer) :name name :kind :call)
          (emitter-relocations emitter))
    (emit-integer buffer 0 4)))

(defun emit-roots-enter (emitter)
  (let* ((buffer (emitter-bytes emitter))
         (windows (eq (backend-contract-abi (emitter-contract emitter)) :win64)))
    (emit-roots-sync emitter)
    (emit-frame-address buffer (if windows 1 7) (emitter-root-header emitter))
    (emit-frame-address buffer (if windows 2 6) (emitter-root-array emitter))
    (emit-root-immediate buffer (if windows 8 2) (length (emitter-root-registers emitter)))
    (emit-root-call emitter "psl_rt_push_roots")))

(defun emit-roots-leave (emitter)
  (emit-frame-address (emitter-bytes emitter)
                      (if (eq (backend-contract-abi (emitter-contract emitter)) :win64) 1 7)
                      (emitter-root-header emitter))
  (emit-root-call emitter "psl_rt_pop_roots"))
