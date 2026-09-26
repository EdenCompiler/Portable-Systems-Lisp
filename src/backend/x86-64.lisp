(in-package #:psl.backend.x86-64)

(defstruct (emitter (:constructor make-emitter
                      (contract signatures signature abi-layouts)))
  contract signatures signature abi-layouts
  return-buffer-slot
  (bytes (byte-buffer))
  (relocations nil)
  (labels (make-hash-table))
  (fixups nil))

(defun slot-displacement (slot &optional (part 0))
  (+ (- (* (1+ slot) 16)) (* part 8)))

(defun emit-slot (buffer opcode register slot &optional (part 0))
  ;; REX.W + MOV with an RBP-relative 32-bit displacement.
  (emit-bytes buffer (if (>= register 8) #x4c #x48)
              opcode (+ #x85 (ash (mod register 8) 3)))
  (emit-integer buffer (slot-displacement slot part) 4))

(defun emit-load-slot (buffer register slot &optional (part 0))
  (emit-slot buffer #x8b register slot part))

(defun emit-store-slot (buffer register slot &optional (part 0))
  (emit-slot buffer #x89 register slot part))

(defun emit-load-stack-argument (buffer index &optional (base 16))
  ;; The return address and saved RBP precede stack arguments.
  (emit-bytes buffer #x48 #x8b #x85)
  (emit-integer buffer (+ base (* index 8)) 4))

(defun emit-push-slot (buffer slot &optional (part 0))
  (emit-bytes buffer #xff #xb5)
  (emit-integer buffer (slot-displacement slot part) 4))

(defun emit-load-xmm-slot (buffer register slot &optional (part 0))
  (emit-bytes buffer #xf3 #x0f #x7e (+ #x85 (ash register 3)))
  (emit-integer buffer (slot-displacement slot part) 4))

(defun emit-store-xmm-slot (buffer register slot &optional (part 0))
  (emit-bytes buffer #x66 #x0f #xd6 (+ #x85 (ash register 3)))
  (emit-integer buffer (slot-displacement slot part) 4))

(defun aggregate-classes (type abi-layouts)
  (when (and (consp type) (eq (first type) :struct))
    (or (gethash (second type) abi-layouts)
        (fail "unsupported C aggregate ABI type ~S" type))))

(defun aggregate-qwords (type abi-layouts)
  (let ((classes (aggregate-classes type abi-layouts)))
    (when classes
      (if (member (first classes) '(:win-direct :win-indirect))
          (ceiling (second classes) 8)
          (length classes)))))

(defun abi-argument-locations (types contract abi-layouts)
  (when (eq (backend-contract-abi contract) :win64)
    (return-from abi-argument-locations
      (win-argument-locations types contract abi-layouts)))
  (let ((general 0) (floating 0) (stack 0)
        (general-registers (backend-contract-argument-registers contract))
        (float-registers (backend-contract-float-argument-registers contract)))
    (loop for type in types
          for classes = (aggregate-classes type abi-layouts)
          collect
          (cond
            ((float-type-p type)
             (if (< floating (length float-registers))
                 (let ((register (nth floating float-registers)))
                   (incf floating)
                   (list :sse register))
                 (let ((index stack))
                   (incf stack)
                   (list :stack index))))
            ((or (integer-type-p type) (pointer-type-p type)
                 (eq type :value))
             (if (< general (length general-registers))
                 (let ((register (nth general general-registers)))
                   (incf general)
                   (list :gp register))
                 (let ((index stack))
                   (incf stack)
                   (list :stack index))))
            (classes
             (if (and (<= (+ general (count :integer classes))
                          (length general-registers))
                      (<= (+ floating (count :sse classes))
                          (length float-registers)))
                 (cons :aggregate-registers
                       (loop for class in classes
                             collect
                             (if (eq class :integer)
                                 (let ((register
                                         (nth general general-registers)))
                                   (incf general)
                                   (list :gp register))
                                 (let ((register
                                         (nth floating float-registers)))
                                   (incf floating)
                                   (list :sse register)))))
                 (let ((index stack))
                   (incf stack (length classes))
                   (list :aggregate-stack index (length classes)))))
            (t (fail "unsupported System V argument type ~S" type))))))

(defun x86-type-width (type contract)
  (cond ((float-type-p type) (if (eq type :f32) 32 64))
        ((or (pointer-type-p type) (eq type :boolean))
         (backend-contract-pointer-bits contract))
        (t (type-width type (backend-contract-pointer-bits contract)))))

(defun normalize-rax (buffer type contract)
  (let ((width (x86-type-width type contract)))
    (case width
      (8 (if (signed-type-p type)
             (emit-bytes buffer #x48 #x0f #xbe #xc0)
             (emit-bytes buffer #x0f #xb6 #xc0)))
      (16 (if (signed-type-p type)
              (emit-bytes buffer #x48 #x0f #xbf #xc0)
              (emit-bytes buffer #x0f #xb7 #xc0)))
      (32 (if (signed-type-p type)
              (emit-bytes buffer #x48 #x63 #xc0)
              (emit-bytes buffer #x89 #xc0)))
      (64 nil)
      (otherwise (fail "internal error: unsupported type width ~A" width)))))

(defun emit-constant (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (value (lir-instruction-value instruction)))
    (emit-bytes buffer #x48 #xb8)
    (emit-integer buffer (if (float-type-p (cdr value))
                             (float-bits (car value) (cdr value))
                             (car value)) 8)
    (unless (float-type-p (cdr value))
      (normalize-rax buffer (cdr value) (emitter-contract emitter)))
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun emit-copy (emitter instruction)
  (unless (eq (lir-instruction-type instruction) :void)
    (let ((buffer (emitter-bytes emitter))
          (words (or (aggregate-qwords (lir-instruction-type instruction)
                                      (emitter-abi-layouts emitter)) 1)))
      (dotimes (part words)
        (emit-load-slot buffer 0 (first (lir-instruction-args instruction)) part)
        (emit-store-slot buffer 0 (lir-instruction-dst instruction) part)))))

(defun emit-convert (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (emit-load-slot buffer 0 (first (lir-instruction-args instruction)))
    (normalize-rax buffer (lir-instruction-type instruction)
                   (emitter-contract emitter))
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun emit-comparison (buffer operator type)
  (emit-bytes buffer #x48 #x39 #xc1 #x0f
              (cond ((equal operator "=") #x94)
                    ((signed-type-p type) #x9c)
                    (t #x92))
              #xc0 #x48 #x0f #xb6 #xc0))

(defun emit-binary-operation (buffer operator type)
  (cond
    ((equal operator "wrap+") (emit-bytes buffer #x48 #x01 #xc8))
    ((equal operator "wrap-")
     (emit-bytes buffer #x48 #x29 #xc1 #x48 #x89 #xc8))
    ((equal operator "wrap*") (emit-bytes buffer #x48 #x0f #xaf #xc1))
    ((equal operator "bits-and") (emit-bytes buffer #x48 #x21 #xc8))
    ((equal operator "shr64")
     (emit-bytes buffer #x48 #x91 #x48 #xd3 #xe8))
    ((member operator '("=" "<") :test #'equal)
     (emit-comparison buffer operator type))
    (t (fail "internal error: unknown operation ~A" operator))))

(defun emit-binary (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (operands (lir-instruction-args instruction))
        (operation (lir-instruction-value instruction)))
    (emit-load-slot buffer 1 (first operands))
    (emit-load-slot buffer 0 (second operands))
    (emit-binary-operation buffer (car operation) (cdr operation))
    (unless (member (car operation) '("=" "<") :test #'equal)
      (normalize-rax buffer (cdr operation) (emitter-contract emitter)))
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun emit-argument (emitter instruction)
  (when (eq (backend-contract-abi (emitter-contract emitter)) :win64)
    (return-from emit-argument (win-emit-argument emitter instruction)))
  (let* ((value (lir-instruction-value instruction))
         (index (car value))
         (location (nth index
                        (abi-argument-locations
                         (signature-arguments (emitter-signature emitter))
                         (emitter-contract emitter)
                         (emitter-abi-layouts emitter))))
         (slot (lir-instruction-dst instruction))
         (buffer (emitter-bytes emitter)))
    (ecase (first location)
      (:gp (emit-store-slot buffer (second location) slot))
      (:sse (emit-store-xmm-slot buffer (second location) slot))
      (:stack
       (emit-load-stack-argument buffer (second location))
       (emit-store-slot buffer 0 slot))
      (:aggregate-registers
       (loop for part-location in (rest location)
             for part from 0
             do (ecase (first part-location)
                  (:gp (emit-store-slot buffer (second part-location)
                                        slot part))
                  (:sse (emit-store-xmm-slot
                         buffer (second part-location) slot part)))))
      (:aggregate-stack
       (dotimes (part (third location))
         (emit-load-stack-argument buffer (+ (second location) part))
         (emit-store-slot buffer 0 slot part))))
    (when (and (not (float-type-p (cdr value)))
               (not (aggregate-qwords (cdr value)
                                      (emitter-abi-layouts emitter)))
               (< (x86-type-width (cdr value) (emitter-contract emitter))
                  (backend-contract-pointer-bits (emitter-contract emitter))))
      (emit-load-slot buffer 0 slot)
      (normalize-rax buffer (cdr value) (emitter-contract emitter))
      (emit-store-slot buffer 0 slot))))

(defun stack-call-parts (slots locations)
  (loop for slot in slots
        for location in locations
        append (case (first location)
                 (:stack (list (cons slot 0)))
                 (:aggregate-stack
                  (loop for part below (third location)
                        collect (cons slot part)))
                 (otherwise nil))))

(defun emit-stack-call-arguments (buffer slots locations)
  (let* ((parts (stack-call-parts slots locations))
         (padding (if (oddp (length parts)) 8 0)))
    (when (plusp padding)
      (emit-bytes buffer #x48 #x83 #xec 8))
    (dolist (part (reverse parts))
      (emit-push-slot buffer (car part) (cdr part)))
    (+ (* 8 (length parts)) padding)))

(defun emit-register-call-arguments (buffer slots locations)
  (loop for slot in slots
        for location in locations
        do (ecase (first location)
             (:gp (emit-load-slot buffer (second location) slot))
             (:sse (emit-load-xmm-slot buffer (second location) slot))
             (:aggregate-registers
              (loop for part-location in (rest location)
                    for part from 0
                    do (ecase (first part-location)
                         (:gp (emit-load-slot buffer (second part-location)
                                              slot part))
                         (:sse (emit-load-xmm-slot
                                buffer (second part-location) slot part)))))
             (:aggregate-stack nil)
             (:stack nil))))

(defun aggregate-return-locations (classes)
  (let ((general 0) (floating 0))
    (loop for class in classes
          collect (ecase class
                    (:integer
                     (prog1 (list :gp (nth general '(0 2)))
                       (incf general)))
                    (:sse
                     (prog1 (list :sse floating)
                       (incf floating)))))))

(defun emit-aggregate-return-parts (buffer slot classes direction)
  (loop for location in (aggregate-return-locations classes)
        for part from 0
        do (ecase (first location)
             (:gp
              (if (eq direction :store)
                  (emit-store-slot buffer (second location) slot part)
                  (emit-load-slot buffer (second location) slot part)))
             (:sse
              (if (eq direction :store)
                  (emit-store-xmm-slot buffer (second location) slot part)
                  (emit-load-xmm-slot buffer (second location) slot part))))))

(defun emit-call-result (emitter instruction)
  (when (eq (backend-contract-abi (emitter-contract emitter)) :win64)
    (return-from emit-call-result
      (win-emit-call-result emitter instruction)))
  (let* ((buffer (emitter-bytes emitter))
         (type (cdr (lir-instruction-value instruction)))
         (slot (lir-instruction-dst instruction))
         (classes (aggregate-classes type (emitter-abi-layouts emitter))))
    (cond
      ((eq type :void) nil)
      ((float-type-p type) (emit-store-xmm-slot buffer 0 slot))
      (classes (emit-aggregate-return-parts buffer slot classes :store))
      (t
       (normalize-rax buffer type (emitter-contract emitter))
       (emit-store-slot buffer 0 slot)))))

(defun emit-call (emitter instruction)
  (when (eq (backend-contract-abi (emitter-contract emitter)) :win64)
    (return-from emit-call (win-emit-call emitter instruction)))
  (let* ((buffer (emitter-bytes emitter))
         (signature (gethash (car (lir-instruction-value instruction))
                             (emitter-signatures emitter)))
         (locations (abi-argument-locations
                     (signature-arguments signature)
                     (emitter-contract emitter)
                     (emitter-abi-layouts emitter)))
         (stack-bytes (emit-stack-call-arguments
                       buffer (lir-instruction-args instruction)
                       locations)))
    (emit-register-call-arguments buffer (lir-instruction-args instruction)
                                  locations)
    (emit-byte buffer #xe8)
    (push (make-relocation :offset (length buffer)
                           :name (car (lir-instruction-value instruction))
                           :kind :call)
          (emitter-relocations emitter))
    (emit-integer buffer 0 4)
    (when (plusp stack-bytes)
      (emit-bytes buffer #x48 #x81 #xc4)
      (emit-integer buffer stack-bytes 4))
    (emit-call-result emitter instruction)))

(defun emit-data-address (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (emit-bytes buffer #x48
                (if (eq (backend-contract-abi (emitter-contract emitter)) :win64)
                    #x8d #x8b)
                #x05)
    (push (make-relocation :offset (length buffer)
                           :name (car (lir-instruction-value instruction))
                           :kind (if (eq (backend-contract-abi
                                           (emitter-contract emitter)) :win64)
                                     :data :got))
          (emitter-relocations emitter))
    (emit-integer buffer 0 4)
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun emit-field-pointer (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (offset (lir-instruction-value instruction)))
    (unless (<= 0 offset #x7fffffff)
      (fail "structure field offset exceeds x86-64 immediate range"))
    (emit-load-slot buffer 0 (first (lir-instruction-args instruction)))
    (emit-bytes buffer #x48 #x05)
    (emit-integer buffer offset 4)
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun emit-pointer-add (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (scale (lir-instruction-value instruction))
        (operands (lir-instruction-args instruction)))
    (unless (<= 1 scale #x7fffffff)
      (fail "pointer element size exceeds x86-64 immediate range"))
    (emit-load-slot buffer 1 (first operands))
    (emit-load-slot buffer 0 (second operands))
    (unless (= scale 1)
      (emit-bytes buffer #x48 #x69 #xc0)
      (emit-integer buffer scale 4))
    (emit-bytes buffer #x48 #x01 #xc8)
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun emit-memory-load (buffer type contract)
  (let ((width (x86-type-width type contract)))
    (case width
      (8 (if (signed-type-p type)
             (emit-bytes buffer #x48 #x0f #xbe #x00)
             (emit-bytes buffer #x0f #xb6 #x00)))
      (16 (if (signed-type-p type)
              (emit-bytes buffer #x48 #x0f #xbf #x00)
              (emit-bytes buffer #x0f #xb7 #x00)))
      (32 (if (signed-type-p type)
              (emit-bytes buffer #x48 #x63 #x00)
              (emit-bytes buffer #x8b #x00)))
      (64 (emit-bytes buffer #x48 #x8b #x00))
      (otherwise (fail "unsupported load width ~A" width)))))

(defun emit-load (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (emit-load-slot buffer 0 (first (lir-instruction-args instruction)))
    (emit-memory-load buffer (lir-instruction-value instruction)
                      (emitter-contract emitter))
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun emit-memory-store (buffer type contract)
  (case (x86-type-width type contract)
    (8 (emit-bytes buffer #x88 #x01))
    (16 (emit-bytes buffer #x66 #x89 #x01))
    (32 (emit-bytes buffer #x89 #x01))
    (64 (emit-bytes buffer #x48 #x89 #x01))
    (otherwise (fail "unsupported store type ~S" type))))

(defun emit-store (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (operands (lir-instruction-args instruction)))
    (emit-load-slot buffer 1 (first operands))
    (emit-load-slot buffer 0 (second operands))
    (emit-memory-store buffer (lir-instruction-value instruction)
                       (emitter-contract emitter))
    (emit-store-slot buffer 0 (lir-instruction-dst instruction))))

(defun reserve-branch (emitter label &rest opcodes)
  (let ((buffer (emitter-bytes emitter)))
    (apply #'emit-bytes buffer opcodes)
    (push (cons (length buffer) label) (emitter-fixups emitter))
    (emit-integer buffer 0 4)))

(defun emit-branch-zero (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (emit-load-slot buffer 0 (first (lir-instruction-args instruction)))
    (emit-bytes buffer #x48 #x85 #xc0)
    (reserve-branch emitter (lir-instruction-value instruction) #x0f #x84)))

(defun emit-label (emitter instruction)
  (let ((label (lir-instruction-value instruction)))
    (when (gethash label (emitter-labels emitter))
      (fail "internal error: duplicate label ~A" label))
    (setf (gethash label (emitter-labels emitter))
          (length (emitter-bytes emitter)))))

(defun emit-return-value (emitter instruction)
  (when (eq (backend-contract-abi (emitter-contract emitter)) :win64)
    (return-from emit-return-value
      (win-emit-return-value emitter instruction)))
  (let* ((buffer (emitter-bytes emitter))
         (type (lir-instruction-type instruction))
         (slot (first (lir-instruction-args instruction)))
         (classes (aggregate-classes type (emitter-abi-layouts emitter))))
    (cond
      ((eq type :void) nil)
      ((float-type-p type) (emit-load-xmm-slot buffer 0 slot))
      (classes (emit-aggregate-return-parts buffer slot classes :load))
      (t (emit-load-slot buffer 0 slot)))))

(defun emit-return (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (emit-return-value emitter instruction)
    (if (eq (backend-contract-abi (emitter-contract emitter)) :win64)
        (emit-bytes buffer #x48 #x8d #x65 0 #x5d #xc3)
        (emit-bytes buffer #xc9 #xc3))))

(defun emit-instruction (emitter instruction)
  (case (lir-instruction-op instruction)
    (:argument (emit-argument emitter instruction))
    (:constant (emit-constant emitter instruction))
    (:copy (emit-copy emitter instruction))
    (:convert (emit-convert emitter instruction))
    (:binary (emit-binary emitter instruction))
    (:call (emit-call emitter instruction))
    (:data-address (emit-data-address emitter instruction))
    (:field-pointer (emit-field-pointer emitter instruction))
    (:pointer-add (emit-pointer-add emitter instruction))
    (:load (emit-load emitter instruction))
    (:store (emit-store emitter instruction))
    (:branch-zero (emit-branch-zero emitter instruction))
    (:jump (reserve-branch emitter (lir-instruction-value instruction) #xe9))
    (:label (emit-label emitter instruction))
    (:return (emit-return emitter instruction))
    (otherwise
     (fail "internal error: unsupported LIR operation ~A"
           (lir-instruction-op instruction)))))

(defun patch-branches (emitter)
  (dolist (fixup (emitter-fixups emitter))
    (let ((destination (gethash (cdr fixup) (emitter-labels emitter))))
      (unless destination
        (fail "internal error: missing label ~A" (cdr fixup)))
      (patch-i32 (emitter-bytes emitter) (car fixup)
                 (- destination (+ (car fixup) 4))))))

(defun emit-prologue (buffer)
  ;; The frame-size field is patched after all LIR registers are known.
  (emit-bytes buffer #x55 #x48 #x89 #xe5 #x48 #x81 #xec 0 0 0 0))

(defun compile-function (function contract signatures abi-layouts)
  (unless (and (eq (backend-contract-architecture contract) :x86-64)
               (member (backend-contract-abi contract)
                       '(:sysv-amd64 :win64)))
    (fail "x86-64 backend requires a supported AMD64 ABI"))
  (let ((emitter (make-emitter contract signatures
                               (lir-function-signature function)
                               abi-layouts)))
    (when (win-indirect-return-p
           (signature-result (lir-function-signature function))
           contract abi-layouts)
      (setf (emitter-return-buffer-slot emitter)
            (lir-function-register-count function)))
    (emit-prologue (emitter-bytes emitter))
    (when (emitter-return-buffer-slot emitter)
      (emit-store-slot (emitter-bytes emitter) 1
                       (emitter-return-buffer-slot emitter)))
    (dolist (instruction (lir-function-instructions function))
      (let ((*source-location* (lir-instruction-source instruction)))
        (emit-instruction emitter instruction)))
    (patch-branches emitter)
    (let ((frame-size
            (* (backend-contract-stack-alignment contract)
               (ceiling (* (+ (lir-function-register-count function)
                              (if (emitter-return-buffer-slot emitter) 1 0))
                           16)
                        (backend-contract-stack-alignment contract)))))
      (patch-i32 (emitter-bytes emitter) 7 frame-size)
    (make-encoded-function
     :name (lir-function-name function)
     :bytes (emitter-bytes emitter)
     :relocations (nreverse (emitter-relocations emitter))
     :frame-size frame-size))))

(defun compile-linux-exit-startup ()
  (let ((buffer (byte-buffer)))
    (emit-bytes buffer #x48 #x31 #xed) ; xor rbp, rbp
    (emit-byte buffer #xe8) ; call main
    (let ((call-offset (length buffer)))
      (emit-integer buffer 0 4)
      (emit-bytes buffer #x89 #xc7) ; mov edi, eax
      (emit-bytes buffer #xb8 #x3c 0 0 0) ; mov eax, 60 (Linux exit)
      (emit-bytes buffer #x0f #x05) ; syscall
      (emit-byte buffer #xf4) ; hlt if exit unexpectedly returns
      (make-encoded-function
       :name "_start" :bytes buffer :frame-size 0
       :relocations (list (make-relocation :offset call-offset
                                          :name "main" :kind :call))))))
