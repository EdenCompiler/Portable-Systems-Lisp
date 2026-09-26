(in-package #:psl.backend.aarch64)

(defstruct (emitter (:constructor make-emitter
                      (contract signatures signature abi-layouts)))
  contract signatures signature abi-layouts
  (bytes (byte-buffer))
  (relocations nil)
  (labels (make-hash-table))
  (fixups nil))

(defun word (buffer bits)
  (emit-integer buffer bits 4))

(defun patch-word (buffer offset bits)
  (dotimes (index 4)
    (setf (aref buffer (+ offset index))
          (ldb (byte 8 (* index 8)) bits))))

(defun register-op (buffer base destination left right)
  (word buffer (logior base destination (ash left 5) (ash right 16))))

(defun mov-immediate (buffer register value)
  (let ((bits (ldb (byte 64 0) value)))
    (word buffer (logior #xd2800000 register
                         (ash (ldb (byte 16 0) bits) 5)))
    (loop for half from 1 below 4
          for piece = (ldb (byte 16 (* half 16)) bits)
          unless (zerop piece)
            do (word buffer (logior #xf2800000 register
                                    (ash half 21) (ash piece 5))))))

(defun slot-address (buffer slot)
  (mov-immediate buffer 16 (* 16 (1+ slot)))
  (register-op buffer #xcb000000 16 29 16))

(defun load-slot (buffer register slot &optional (offset 0))
  (slot-address buffer slot)
  (word buffer (logior #xf9400000 register (ash (floor offset 8) 10)
                       (ash 16 5))))

(defun store-slot (buffer register slot &optional (offset 0))
  (slot-address buffer slot)
  (word buffer (logior #xf9000000 register (ash (floor offset 8) 10)
                       (ash 16 5))))

(defun load-slot-part (buffer register slot offset width)
  (slot-address buffer slot)
  (word buffer (logior (if (= width 32) #xb9400000 #xf9400000)
                       register (ash (floor offset (/ width 8)) 10)
                       (ash 16 5))))

(defun store-slot-part (buffer register slot offset width)
  (slot-address buffer slot)
  (word buffer (logior (if (= width 32) #xb9000000 #xf9000000)
                       register (ash (floor offset (/ width 8)) 10)
                       (ash 16 5))))

(defun stack-address (buffer offset &optional incoming-p)
  (mov-immediate buffer 17 (+ offset (if incoming-p 16 0)))
  (if incoming-p
      (register-op buffer #x8b000000 16 29 17)
      (progn
        (word buffer #x910003f0) ; mov x16, sp
        (register-op buffer #x8b000000 16 16 17))))

(defun load-stack (buffer register offset &optional incoming-p)
  (stack-address buffer offset incoming-p)
  (word buffer (logior #xf9400000 register (ash 16 5))))

(defun store-stack (buffer register offset)
  (stack-address buffer offset)
  (word buffer (logior #xf9000000 register (ash 16 5))))

(defun adjust-stack (buffer size subtract-p)
  (loop while (plusp size)
        for chunk = (min size 4095)
        do (word buffer (logior (if subtract-p #xd1000000 #x91000000)
                                (ash chunk 10) (ash 31 5) 31))
           (decf size chunk)))

(defun scalar-width (type)
  (cond ((eq type :f32) 32)
        ((eq type :f64) 64)
        ((or (pointer-type-p type) (eq type :value)
             (eq type :boolean)) 64)
        (t (type-width type 64))))

(defun normalize (buffer register type)
  (let ((width (scalar-width type)))
    (when (< width 64)
      (word buffer (logior (if (signed-type-p type)
                              #x93400000 #xd3400000)
                          register (ash register 5)
                          (ash (1- width) 10))))))

(defun aggregate-info (type layouts)
  (when (and (consp type) (eq (first type) :struct))
    (or (gethash (second type) layouts)
        (fail "unsupported AAPCS64 aggregate ~S" type))))

(defun aggregate-size (info)
  (if (eq (first info) :hfa)
      (+ (car (last (third info)))
         (/ (scalar-width (second info)) 8))
      (second info)))

(defun aggregate-words (info)
  (ceiling (aggregate-size info) 8))

(defun stack-location (size offset)
  (list :stack offset size))

(defun argument-locations (types layouts)
  (let ((general 0) (floating 0) (stack 0))
    (loop for type in types
          for info = (aggregate-info type layouts)
          collect
          (cond
            ((float-type-p type)
             (if (< floating 8)
                 (prog1 (list :fp floating type) (incf floating))
                 (prog1 (stack-location 8 stack) (incf stack 8))))
            ((or (integer-type-p type) (pointer-type-p type)
                 (eq type :value) (eq type :boolean))
             (if (< general 8)
                 (prog1 (list :gp general) (incf general))
                 (prog1 (stack-location 8 stack) (incf stack 8))))
            ((and info (eq (first info) :hfa))
             (let ((count (length (third info))))
               (if (<= (+ floating count) 8)
                   (prog1 (list :hfa floating (second info) (third info))
                     (incf floating count))
                   (prog1 (stack-location (* 8 (aggregate-words info)) stack)
                     (incf stack (* 8 (aggregate-words info)))
                     (setf floating 8)))))
            (info
             (let ((count (aggregate-words info)))
               (if (<= (+ general count) 8)
                   (prog1 (list :aggregate-gp general count)
                     (incf general count))
                   (prog1 (stack-location (* 8 count) stack)
                     (incf stack (* 8 count))
                     (setf general 8)))))
            (t (fail "unsupported AAPCS64 argument type ~S" type))))))

(defun float-to-general (buffer general floating type)
  (word buffer (logior (if (eq type :f32) #x1e260000 #x9e660000)
                       general (ash floating 5))))

(defun general-to-float (buffer floating general type)
  (word buffer (logior (if (eq type :f32) #x1e270000 #x9e670000)
                       floating (ash general 5))))

(defun move-aggregate-gp (buffer slot start count inbound-p)
  (dotimes (part count)
    (if inbound-p
        (store-slot buffer (+ start part) slot (* part 8))
        (load-slot buffer (+ start part) slot (* part 8)))))

(defun move-hfa (buffer slot start type offsets inbound-p)
  (loop for offset in offsets for part from 0
        for register = (+ start part)
        for width = (scalar-width type)
        do (if inbound-p
               (progn
                 (float-to-general buffer 9 register type)
                 (store-slot-part buffer 9 slot offset width))
               (progn
                 (load-slot-part buffer 9 slot offset width)
                 (general-to-float buffer register 9 type)))))

(defun move-stack-argument (buffer slot location inbound-p)
  (destructuring-bind (kind offset size) location
    (declare (ignore kind))
    (loop for part below (ceiling size 8)
          for byte-offset = (+ offset (* part 8))
          do (if inbound-p
                 (progn (load-stack buffer 9 byte-offset t)
                        (store-slot buffer 9 slot (* part 8)))
                 (progn (load-slot buffer 9 slot (* part 8))
                        (store-stack buffer 9 byte-offset))))))

(defun move-argument (buffer slot type location inbound-p)
  (case (first location)
    (:gp
     (let ((register (second location)))
       (if inbound-p
           (progn (register-op buffer #xaa0003e0 9 31 register)
                  (normalize buffer 9 type)
                  (store-slot buffer 9 slot))
           (load-slot buffer register slot))))
    (:fp
     (if inbound-p
         (progn (float-to-general buffer 9 (second location) type)
                (store-slot buffer 9 slot))
         (progn (load-slot buffer 9 slot)
                (general-to-float buffer (second location) 9 type))))
    (:aggregate-gp
     (move-aggregate-gp buffer slot (second location) (third location)
                        inbound-p))
    (:hfa
     (move-hfa buffer slot (second location) (third location)
               (fourth location) inbound-p))
    (:stack (move-stack-argument buffer slot location inbound-p))))

(defun emit-argument (emitter instruction)
  (let* ((signature (emitter-signature emitter))
         (index (car (lir-instruction-value instruction)))
         (type (cdr (lir-instruction-value instruction)))
         (location (nth index (argument-locations
                               (signature-arguments signature)
                               (emitter-abi-layouts emitter)))))
    (move-argument (emitter-bytes emitter)
                   (lir-instruction-dst instruction) type location t)))

(defun emit-constant (emitter instruction)
  (let* ((value (lir-instruction-value instruction))
         (type (cdr value))
         (buffer (emitter-bytes emitter)))
    (mov-immediate buffer 9 (if (float-type-p type)
                                (float-bits (car value) type)
                                (car value)))
    (unless (float-type-p type) (normalize buffer 9 type))
    (store-slot buffer 9 (lir-instruction-dst instruction))))

(defun emit-copy (emitter instruction)
  (unless (eq (lir-instruction-type instruction) :void)
    (let* ((buffer (emitter-bytes emitter))
           (info (aggregate-info (lir-instruction-type instruction)
                                 (emitter-abi-layouts emitter))))
      (dotimes (part (if info (aggregate-words info) 1))
        (load-slot buffer 9 (first (lir-instruction-args instruction))
                   (* part 8))
        (store-slot buffer 9 (lir-instruction-dst instruction)
                    (* part 8))))))

(defun emit-convert (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (load-slot buffer 9 (first (lir-instruction-args instruction)))
    (normalize buffer 9 (lir-instruction-type instruction))
    (store-slot buffer 9 (lir-instruction-dst instruction))))

(defun emit-binary (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (arguments (lir-instruction-args instruction))
         (operation (car (lir-instruction-value instruction)))
         (type (cdr (lir-instruction-value instruction))))
    (load-slot buffer 9 (first arguments))
    (load-slot buffer 10 (second arguments))
    (cond
      ((equal operation "wrap+")
       (register-op buffer #x8b000000 9 9 10))
      ((equal operation "wrap-")
       (register-op buffer #xcb000000 9 9 10))
      ((equal operation "wrap*")
       (register-op buffer #x9b007c00 9 9 10))
      ((equal operation "bits-and")
       (register-op buffer #x8a000000 9 9 10))
      ((equal operation "shr64")
       (register-op buffer #x9ac02400 9 9 10))
      ((member operation '("=" "<") :test #'equal)
       (register-op buffer #xeb00001f 31 9 10)
       (word buffer (logior #x9a9f07e0 9
                            (ash (cond ((equal operation "=") 1)
                                       ((signed-type-p type) 10)
                                       (t 2)) 12))))
      (t (fail "unsupported AArch64 operation ~A" operation)))
    (unless (member operation '("=" "<") :test #'equal)
      (normalize buffer 9 type))
    (store-slot buffer 9 (lir-instruction-dst instruction))))

(defun return-location (type layouts)
  (let ((info (aggregate-info type layouts)))
    (cond ((eq type :void) nil)
          ((float-type-p type) (list :fp 0 type))
          ((and info (eq (first info) :hfa))
           (list :hfa 0 (second info) (third info)))
          (info (list :aggregate-gp 0 (aggregate-words info)))
          (t (list :gp 0)))))

(defun outgoing-stack-size (locations)
  (let ((used 0))
    (dolist (location locations)
      (when (eq (first location) :stack)
        (setf used (max used (+ (second location) (third location))))))
    (* 16 (ceiling used 16))))

(defun emit-call (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (name (car (lir-instruction-value instruction)))
         (signature (gethash name (emitter-signatures emitter)))
         (locations (argument-locations (signature-arguments signature)
                                        (emitter-abi-layouts emitter)))
         (stack-size (outgoing-stack-size locations)))
    (adjust-stack buffer stack-size t)
    (loop for slot in (lir-instruction-args instruction)
          for type in (signature-arguments signature)
          for location in locations
          do (move-argument buffer slot type location nil))
    (push (make-relocation :offset (length buffer) :name name :kind :call)
          (emitter-relocations emitter))
    (word buffer #x94000000)
    (adjust-stack buffer stack-size nil)
    (unless (eq (cdr (lir-instruction-value instruction)) :void)
      (move-argument buffer (lir-instruction-dst instruction)
                     (cdr (lir-instruction-value instruction))
                     (return-location (cdr (lir-instruction-value instruction))
                                      (emitter-abi-layouts emitter)) t))))

(defun emit-data-address (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (name (car (lir-instruction-value instruction))))
    (push (make-relocation :offset (length buffer) :name name :kind :got-page)
          (emitter-relocations emitter))
    (word buffer #x90000009)
    (push (make-relocation :offset (length buffer) :name name :kind :got-lo12)
          (emitter-relocations emitter))
    (word buffer #xf9400129)
    (store-slot buffer 9 (lir-instruction-dst instruction))))

(defun emit-field-pointer (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (load-slot buffer 9 (first (lir-instruction-args instruction)))
    (mov-immediate buffer 10 (lir-instruction-value instruction))
    (register-op buffer #x8b000000 9 9 10)
    (store-slot buffer 9 (lir-instruction-dst instruction))))

(defun emit-pointer-add (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (arguments (lir-instruction-args instruction)))
    (load-slot buffer 9 (first arguments))
    (load-slot buffer 10 (second arguments))
    (unless (= (lir-instruction-value instruction) 1)
      (mov-immediate buffer 11 (lir-instruction-value instruction))
      (register-op buffer #x9b007c00 10 10 11))
    (register-op buffer #x8b000000 9 9 10)
    (store-slot buffer 9 (lir-instruction-dst instruction))))

(defun memory-opcode (width signed-p store-p)
  (ecase width
    (8 (if store-p #x39000000 (if signed-p #x39800000 #x39400000)))
    (16 (if store-p #x79000000 (if signed-p #x79800000 #x79400000)))
    (32 (if store-p #xb9000000 (if signed-p #xb9800000 #xb9400000)))
    (64 (if store-p #xf9000000 #xf9400000))))

(defun emit-load (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (type (lir-instruction-value instruction)))
    (load-slot buffer 9 (first (lir-instruction-args instruction)))
    (word buffer (logior (memory-opcode (scalar-width type)
                                         (signed-type-p type) nil)
                         10 (ash 9 5)))
    (store-slot buffer 10 (lir-instruction-dst instruction))))

(defun emit-store (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (arguments (lir-instruction-args instruction))
        (type (lir-instruction-value instruction)))
    (load-slot buffer 9 (first arguments))
    (load-slot buffer 10 (second arguments))
    (word buffer (logior (memory-opcode (scalar-width type) nil t)
                         10 (ash 9 5)))
    (store-slot buffer 10 (lir-instruction-dst instruction))))

(defun reserve-branch (emitter label base bits)
  (let ((offset (length (emitter-bytes emitter))))
    (push (list offset label base bits) (emitter-fixups emitter))
    (word (emitter-bytes emitter) base)))

(defun emit-branch-zero (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (load-slot buffer 9 (first (lir-instruction-args instruction)))
    (reserve-branch emitter (lir-instruction-value instruction)
                    #xb4000009 19)))

(defun emit-label (emitter instruction)
  (let ((label (lir-instruction-value instruction)))
    (when (gethash label (emitter-labels emitter))
      (fail "duplicate AArch64 label ~A" label))
    (setf (gethash label (emitter-labels emitter))
          (length (emitter-bytes emitter)))))

(defun emit-return (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (type (lir-instruction-type instruction)))
    (unless (eq type :void)
      (move-argument buffer (first (lir-instruction-args instruction)) type
                     (return-location type (emitter-abi-layouts emitter)) nil))
    (word buffer #x910003bf) ; mov sp, x29
    (word buffer #xa8c17bfd) ; ldp x29, x30, [sp], #16
    (word buffer #xd65f03c0)))

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
    (:jump (reserve-branch emitter (lir-instruction-value instruction)
                           #x14000000 26))
    (:label (emit-label emitter instruction))
    (:return (emit-return emitter instruction))
    (otherwise (fail "unsupported AArch64 LIR operation ~A"
                     (lir-instruction-op instruction)))))

(defun patch-branches (emitter)
  (dolist (fixup (emitter-fixups emitter))
    (destructuring-bind (offset label base bits) fixup
      (let* ((destination (gethash label (emitter-labels emitter)))
             (delta (and destination (/ (- destination offset) 4))))
        (unless (and destination (<= (- (ash 1 (1- bits))) delta
                                     (1- (ash 1 (1- bits)))))
          (fail "AArch64 branch target ~A is missing or out of range" label))
        (patch-word (emitter-bytes emitter) offset
                    (logior base
                            (ash (ldb (byte bits 0) delta)
                                 (if (= bits 19) 5 0))))))))

(defun emit-prologue (buffer frame-size)
  (word buffer #xa9bf7bfd) ; stp x29, x30, [sp, #-16]!
  (word buffer #x910003fd) ; mov x29, sp
  (adjust-stack buffer frame-size t))

(defun compile-function (function contract signatures abi-layouts)
  (unless (and (eq (backend-contract-architecture contract) :aarch64)
               (eq (backend-contract-abi contract) :aapcs64))
    (fail "AArch64 backend requires AAPCS64"))
  (let* ((frame-size (* 16 (lir-function-register-count function)))
         (emitter (make-emitter contract signatures
                                (lir-function-signature function)
                                abi-layouts)))
    (emit-prologue (emitter-bytes emitter) frame-size)
    (dolist (instruction (lir-function-instructions function))
      (let ((*source-location* (lir-instruction-source instruction)))
        (emit-instruction emitter instruction)))
    (patch-branches emitter)
    (make-encoded-function
     :name (lir-function-name function)
     :bytes (emitter-bytes emitter)
     :relocations (nreverse (emitter-relocations emitter))
     :frame-size frame-size)))
