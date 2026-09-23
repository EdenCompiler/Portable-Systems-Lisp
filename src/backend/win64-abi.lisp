(in-package #:psl.backend.x86-64)

(defun win-aggregate-layout (type abi-layouts)
  (when (and (consp type) (eq (first type) :struct))
    (or (gethash (second type) abi-layouts)
        (fail "unsupported Windows C aggregate ABI type ~S" type))))

(defun win-indirect-return-p (type contract abi-layouts)
  (and (eq (backend-contract-abi contract) :win64)
       (eq (first (win-aggregate-layout type abi-layouts)) :win-indirect)))

(defun win-aggregate-size (type abi-layouts)
  (second (win-aggregate-layout type abi-layouts)))

(defun win-argument-location (type position contract abi-layouts)
  (let ((layout (win-aggregate-layout type abi-layouts))
        (registers (backend-contract-argument-registers contract)))
    (cond
      ((>= position 4)
       (list (if (and layout (eq (first layout) :win-indirect))
                 :stack-pointer :stack)
             (- position 4)))
      ((and layout (eq (first layout) :win-indirect))
       (list :gp-pointer (nth position registers)))
      ((float-type-p type)
       (list :sse position))
      (t (list :gp (nth position registers))))))

(defun win-argument-locations (types contract abi-layouts &optional hidden-return)
  (loop for type in types
        for position from (if hidden-return 1 0)
        collect (win-argument-location type position contract abi-layouts)))

(defun win-emit-lea-slot (buffer register slot)
  (emit-bytes buffer (if (>= register 8) #x4c #x48)
              #x8d (+ #x85 (ash (mod register 8) 3)))
  (emit-integer buffer (slot-displacement slot) 4))

(defun win-emit-move-to-rax (buffer register)
  (emit-bytes buffer (if (>= register 8) #x4c #x48)
              #x89 (+ #xc0 (ash (mod register 8) 3))))

(defun win-emit-load-r10-from-rax (buffer offset)
  (emit-bytes buffer #x4c #x8b #x90)
  (emit-integer buffer offset 4))

(defun win-emit-store-r10-at-rax (buffer offset)
  (emit-bytes buffer #x4c #x89 #x90)
  (emit-integer buffer offset 4))

(defun win-copy-byte-from-pointer (buffer destination-slot offset)
  (emit-bytes buffer #x44 #x0f #xb6 #x90)
  (emit-integer buffer offset 4)
  (emit-bytes buffer #x44 #x88 #x95)
  (emit-integer buffer (+ (slot-displacement destination-slot) offset) 4))

(defun win-copy-from-pointer (buffer destination-slot source-register size)
  (win-emit-move-to-rax buffer source-register)
  (dotimes (part (floor size 8))
    (win-emit-load-r10-from-rax buffer (* part 8))
    (emit-store-slot buffer 10 destination-slot part))
  (loop for offset from (* 8 (floor size 8)) below size
        do (win-copy-byte-from-pointer buffer destination-slot offset)))

(defun win-emit-argument (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (value (lir-instruction-value instruction))
         (slot (lir-instruction-dst instruction))
         (type (cdr value))
         (hidden (not (null (emitter-return-buffer-slot emitter))))
         (location (nth (car value)
                        (win-argument-locations
                         (signature-arguments (emitter-signature emitter))
                         (emitter-contract emitter)
                         (emitter-abi-layouts emitter) hidden))))
    (ecase (first location)
      (:gp (emit-store-slot buffer (second location) slot))
      (:sse (emit-store-xmm-slot buffer (second location) slot))
      (:stack
       (emit-load-stack-argument buffer (second location) 48)
       (emit-store-slot buffer 0 slot))
      (:gp-pointer
       (win-copy-from-pointer buffer slot (second location)
                              (win-aggregate-size type
                                                  (emitter-abi-layouts emitter))))
      (:stack-pointer
       (emit-load-stack-argument buffer (second location) 48)
       (win-copy-from-pointer buffer slot 0
                              (win-aggregate-size type
                                                  (emitter-abi-layouts emitter)))))
    (when (and (not (float-type-p type))
               (not (aggregate-qwords type (emitter-abi-layouts emitter)))
               (< (x86-type-width type (emitter-contract emitter)) 64))
      (emit-load-slot buffer 0 slot)
      (normalize-rax buffer type (emitter-contract emitter))
      (emit-store-slot buffer 0 slot))))

(defun win-emit-store-stack-slot (buffer index)
  (emit-bytes buffer #x48 #x89 #x84 #x24)
  (emit-integer buffer (+ 32 (* index 8)) 4))

(defun win-emit-prepare-argument (buffer slot location)
  (ecase (first location)
    ((:gp :stack) (emit-load-slot buffer 0 slot))
    ((:gp-pointer :stack-pointer) (win-emit-lea-slot buffer 0 slot))
    (:sse nil)))

(defun win-emit-stack-arguments (buffer slots locations)
  (loop for slot in slots
        for location in locations
        when (member (first location) '(:stack :stack-pointer))
          do (win-emit-prepare-argument buffer slot location)
             (win-emit-store-stack-slot buffer (second location))))

(defun win-emit-register-arguments (buffer slots locations)
  (loop for slot in slots
        for location in locations
        do (ecase (first location)
             ((:gp :gp-pointer)
              (if (eq (first location) :gp-pointer)
                  (win-emit-lea-slot buffer (second location) slot)
                  (emit-load-slot buffer (second location) slot)))
             (:sse (emit-load-xmm-slot buffer (second location) slot))
             ((:stack :stack-pointer) nil))))

(defun win-emit-call (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (signature (gethash (car (lir-instruction-value instruction))
                             (emitter-signatures emitter)))
         (hidden (win-indirect-return-p
                  (signature-result signature) (emitter-contract emitter)
                  (emitter-abi-layouts emitter)))
         (locations (win-argument-locations
                     (signature-arguments signature) (emitter-contract emitter)
                     (emitter-abi-layouts emitter) hidden))
         (extra (max 0 (- (+ (length locations) (if hidden 1 0)) 4)))
         (stack-bytes (* 16 (ceiling (+ 32 (* extra 8)) 16))))
    (emit-bytes buffer #x48 #x81 #xec)
    (emit-integer buffer stack-bytes 4)
    (win-emit-stack-arguments buffer (lir-instruction-args instruction)
                              locations)
    (win-emit-register-arguments buffer (lir-instruction-args instruction)
                                 locations)
    (when hidden
      (win-emit-lea-slot buffer 1 (lir-instruction-dst instruction)))
    (emit-byte buffer #xe8)
    (push (make-relocation :offset (length buffer)
                           :name (car (lir-instruction-value instruction))
                           :kind :call)
          (emitter-relocations emitter))
    (emit-integer buffer 0 4)
    (emit-bytes buffer #x48 #x81 #xc4)
    (emit-integer buffer stack-bytes 4)
    (win-emit-call-result emitter instruction)))

(defun win-emit-call-result (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (type (cdr (lir-instruction-value instruction)))
         (slot (lir-instruction-dst instruction)))
    (unless (or (eq type :void)
                (win-indirect-return-p type (emitter-contract emitter)
                                       (emitter-abi-layouts emitter)))
      (if (float-type-p type)
          (emit-store-xmm-slot buffer 0 slot)
          (progn
            (unless (win-aggregate-layout type (emitter-abi-layouts emitter))
              (normalize-rax buffer type (emitter-contract emitter)))
            (emit-store-slot buffer 0 slot))))))

(defun win-copy-byte-to-pointer (buffer source-slot offset)
  (emit-bytes buffer #x44 #x8a #x95)
  (emit-integer buffer (+ (slot-displacement source-slot) offset) 4)
  (emit-bytes buffer #x44 #x88 #x90)
  (emit-integer buffer offset 4))

(defun win-emit-indirect-return (emitter slot)
  (let ((buffer (emitter-bytes emitter))
        (size (win-aggregate-size
               (signature-result (emitter-signature emitter))
               (emitter-abi-layouts emitter))))
    (emit-load-slot buffer 0 (emitter-return-buffer-slot emitter))
    (dotimes (part (floor size 8))
      (emit-load-slot buffer 10 slot part)
      (win-emit-store-r10-at-rax buffer (* part 8)))
    (loop for offset from (* 8 (floor size 8)) below size
          do (win-copy-byte-to-pointer buffer slot offset))))

(defun win-emit-return-value (emitter instruction)
  (let ((type (lir-instruction-type instruction))
        (slot (first (lir-instruction-args instruction)))
        (buffer (emitter-bytes emitter)))
    (cond
      ((eq type :void) nil)
      ((emitter-return-buffer-slot emitter)
       (win-emit-indirect-return emitter slot))
      ((float-type-p type) (emit-load-xmm-slot buffer 0 slot))
      (t (emit-load-slot buffer 0 slot)))))
