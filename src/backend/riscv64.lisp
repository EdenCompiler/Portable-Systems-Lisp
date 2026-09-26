(in-package #:psl.backend.riscv64)

(defstruct (emitter (:constructor make-emitter
                      (contract signatures signature abi-layouts)))
  contract signatures signature abi-layouts
  (bytes (byte-buffer))
  (relocations nil)
  (local-labels nil)
  (labels (make-hash-table))
  (fixups nil))

(defun word (buffer value)
  (emit-integer buffer value 4))

(defun patch-word (buffer offset value)
  (dotimes (index 4)
    (setf (aref buffer (+ offset index))
          (ldb (byte 8 (* 8 index)) value))))

(defun r-type (buffer opcode destination left right function3 function7)
  (word buffer (logior opcode (ash destination 7) (ash function3 12)
                       (ash left 15) (ash right 20) (ash function7 25))))

(defun i-type (buffer opcode destination source function3 immediate)
  (word buffer (logior opcode (ash destination 7) (ash function3 12)
                       (ash source 15) (ash (ldb (byte 12 0) immediate) 20))))

(defun s-type (buffer opcode source value function3 immediate)
  (let ((bits (ldb (byte 12 0) immediate)))
    (word buffer (logior opcode (ash (ldb (byte 5 0) bits) 7)
                         (ash function3 12) (ash source 15)
                         (ash value 20) (ash (ldb (byte 7 5) bits) 25)))))

(defun b-word (left right function3 displacement)
  (let ((bits (ldb (byte 13 0) displacement)))
    (logior #x63 (ash (ldb (byte 1 11) bits) 7)
            (ash (ldb (byte 4 1) bits) 8)
            (ash function3 12) (ash left 15) (ash right 20)
            (ash (ldb (byte 6 5) bits) 25)
            (ash (ldb (byte 1 12) bits) 31))))

(defun b-type (buffer left right function3 displacement)
  (word buffer (b-word left right function3 displacement)))

(defun jal-word (destination displacement)
  (let ((bits (ldb (byte 21 0) displacement)))
    (logior #x6f (ash destination 7)
            (ash (ldb (byte 8 12) bits) 12)
            (ash (ldb (byte 1 11) bits) 20)
            (ash (ldb (byte 10 1) bits) 21)
            (ash (ldb (byte 1 20) bits) 31))))

(defun move-register (buffer destination source)
  (i-type buffer #x13 destination source 0 0))

(defun load-immediate (buffer register value)
  (let ((bits (ldb (byte 64 0) value)) (started nil))
    (loop for shift from 56 downto 0 by 8
          for piece = (ldb (byte 8 shift) bits)
          when (or started (not (zerop piece)) (= shift 0))
            do (if started
                   (progn
                     (i-type buffer #x13 register register 1 8)
                     (unless (zerop piece)
                       (i-type buffer #x13 register register 0 piece)))
                   (progn
                     (i-type buffer #x13 register 0 0 piece)
                     (setf started t))))))

(defun stack-adjust (buffer amount subtract-p)
  (when (plusp amount)
    (load-immediate buffer 7 amount)
    (r-type buffer #x33 2 2 7 0 (if subtract-p 32 0))))

(defun slot-address (buffer slot)
  (load-immediate buffer 7 (* 16 (1+ slot)))
  (r-type buffer #x33 7 8 7 0 32))

(defun load-slot (buffer register slot &optional (offset 0))
  (slot-address buffer slot)
  (i-type buffer #x03 register 7 3 offset))

(defun store-slot (buffer register slot &optional (offset 0))
  (slot-address buffer slot)
  (s-type buffer #x23 7 register 3 offset))

(defun load-slot-width (buffer register slot offset width)
  (slot-address buffer slot)
  (i-type buffer #x03 register 7 (if (= width 32) 6 3) offset))

(defun store-slot-width (buffer register slot offset width)
  (slot-address buffer slot)
  (s-type buffer #x23 7 register (if (= width 32) 2 3) offset))

(defun stack-address (buffer offset incoming-p)
  (load-immediate buffer 7 (+ offset (if incoming-p 16 0)))
  (r-type buffer #x33 7 (if incoming-p 8 2) 7 0 0))

(defun load-stack (buffer register offset incoming-p)
  (stack-address buffer offset incoming-p)
  (i-type buffer #x03 register 7 3 0))

(defun store-stack (buffer register offset)
  (stack-address buffer offset nil)
  (s-type buffer #x23 7 register 3 0))

(defun scalar-width (type)
  (cond ((eq type :f32) 32)
        ((eq type :f64) 64)
        ((or (pointer-type-p type) (eq type :value)
             (eq type :boolean)) 64)
        (t (type-width type 64))))

(defun normalize (buffer register type &optional abi-p)
  (let ((width (scalar-width type)))
    (when (< width 64)
      (let ((shift (- 64 width)))
        (i-type buffer #x13 register register 1 shift)
        (i-type buffer #x13 register register 5
                (logior shift
                        (if (or (signed-type-p type)
                                (and abi-p (= width 32)))
                            #x400 0)))))))

(defun aggregate-info (type layouts)
  (when (and (consp type) (eq (first type) :struct))
    (or (gethash (second type) layouts)
        (fail "unsupported RISC-V C aggregate ~S" type))))

(defun aggregate-size (info)
  (if (eq (first info) :rv-fields) (third info) (second info)))

(defun aggregate-words (info)
  (ceiling (aggregate-size info) 8))

(defun part (kind index offset width type)
  (list kind index offset width type))

(defun general-parts (size general stack)
  (let ((parts nil))
    (dotimes (index (ceiling size 8))
      (let ((offset (* index 8)))
        (if (< general 8)
            (progn
              (push (part :gp (+ 10 general) offset 64 nil) parts)
              (incf general))
            (progn
              (push (part :stack stack offset 64 nil) parts)
              (incf stack 8)))))
    (values (nreverse parts) general stack)))

(defun special-fields-p (info general floating)
  (and (eq (first info) :rv-fields)
       (let ((fields (second info)))
         (and (<= (+ floating
                     (count-if (lambda (field)
                                 (float-type-p (cdr field))) fields)) 8)
              (<= (+ general
                     (count-if-not (lambda (field)
                                     (float-type-p (cdr field))) fields)) 8)))))

(defun special-field-parts (fields general floating)
  (let ((parts nil))
    (dolist (field fields)
      (let ((offset (car field)) (type (cdr field)))
        (if (float-type-p type)
            (progn
              (push (part :fp (+ 10 floating) offset
                          (scalar-width type) type) parts)
              (incf floating))
            (progn
              (push (part :gp (+ 10 general) offset
                          (scalar-width type) type) parts)
              (incf general)))))
    (values (nreverse parts) general floating)))

(defun argument-locations (types layouts)
  (let ((general 0) (floating 0) (stack 0) (locations nil))
    (dolist (type types)
      (let ((info (aggregate-info type layouts)))
        (cond
          ((and (float-type-p type) (< floating 8))
           (push (list :scalar
                       (part :fp (+ 10 floating) 0 (scalar-width type) type))
                 locations)
           (incf floating))
          ((and info (special-fields-p info general floating))
           (multiple-value-bind (parts next-general next-floating)
               (special-field-parts (second info) general floating)
             (push (cons :aggregate parts) locations)
             (setf general next-general floating next-floating)))
          (t
           (multiple-value-bind (parts next-general next-stack)
               (general-parts (if info (aggregate-size info) 8)
                              general stack)
             (push (cons (if info :aggregate :scalar) parts) locations)
             (setf general next-general stack next-stack))))))
    (nreverse locations)))

(defun float-to-general (buffer general floating type)
  (word buffer (logior (if (eq type :f32) #xe0000053 #xe2000053)
                       (ash floating 15) (ash general 7))))

(defun general-to-float (buffer floating general type)
  (word buffer (logior (if (eq type :f32) #xf0000053 #xf2000053)
                       (ash general 15) (ash floating 7))))

(defun move-part (buffer slot part inbound-p &optional scalar-type)
  (destructuring-bind (kind index offset width type) part
    (if inbound-p
        (progn
          (ecase kind
            (:gp (move-register buffer 5 index))
            (:fp (float-to-general buffer 5 index type))
            (:stack (load-stack buffer 5 index t)))
          (store-slot-width buffer 5 slot offset width))
        (progn
          (load-slot-width buffer 5 slot offset width)
          (when (and scalar-type (not (float-type-p scalar-type))
                     (= (scalar-width scalar-type) 32)
                     (not (signed-type-p scalar-type)))
            (normalize buffer 5 scalar-type t))
          (ecase kind
            (:gp (move-register buffer index 5))
            (:fp (general-to-float buffer index 5 type))
            (:stack (store-stack buffer 5 index)))))))

(defun move-location (buffer slot type location inbound-p)
  (dolist (part (rest location))
    (move-part buffer slot part inbound-p
               (when (eq (first location) :scalar) type)))
  (when (and (eq (first location) :scalar)
             (not (float-type-p type)) inbound-p)
    (load-slot buffer 5 slot)
    (normalize buffer 5 type)
    (store-slot buffer 5 slot)))

(defun emit-argument (emitter instruction)
  (let* ((index (car (lir-instruction-value instruction)))
         (type (cdr (lir-instruction-value instruction)))
         (locations (argument-locations
                     (signature-arguments (emitter-signature emitter))
                     (emitter-abi-layouts emitter))))
    (move-location (emitter-bytes emitter)
                   (lir-instruction-dst instruction) type
                   (nth index locations) t)))

(defun emit-constant (emitter instruction)
  (let* ((value (lir-instruction-value instruction))
         (type (cdr value))
         (buffer (emitter-bytes emitter)))
    (load-immediate buffer 5 (if (float-type-p type)
                                 (float-bits (car value) type)
                                 (car value)))
    (unless (float-type-p type) (normalize buffer 5 type))
    (store-slot buffer 5 (lir-instruction-dst instruction))))

(defun emit-copy (emitter instruction)
  (unless (eq (lir-instruction-type instruction) :void)
    (let* ((buffer (emitter-bytes emitter))
           (info (aggregate-info (lir-instruction-type instruction)
                                 (emitter-abi-layouts emitter))))
      (dotimes (index (if info (aggregate-words info) 1))
        (load-slot buffer 5 (first (lir-instruction-args instruction))
                   (* index 8))
        (store-slot buffer 5 (lir-instruction-dst instruction)
                    (* index 8))))))

(defun emit-convert (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (load-slot buffer 5 (first (lir-instruction-args instruction)))
    (normalize buffer 5 (lir-instruction-type instruction))
    (store-slot buffer 5 (lir-instruction-dst instruction))))

(defun emit-binary (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (arguments (lir-instruction-args instruction))
         (operation (car (lir-instruction-value instruction)))
         (type (cdr (lir-instruction-value instruction))))
    (load-slot buffer 5 (first arguments))
    (load-slot buffer 6 (second arguments))
    (cond
      ((equal operation "wrap+") (r-type buffer #x33 5 5 6 0 0))
      ((equal operation "wrap-") (r-type buffer #x33 5 5 6 0 32))
      ((equal operation "wrap*") (r-type buffer #x33 5 5 6 0 1))
      ((equal operation "bits-and") (r-type buffer #x33 5 5 6 7 0))
      ((equal operation "shr64") (r-type buffer #x33 5 5 6 5 0))
      ((equal operation "=")
       (r-type buffer #x33 5 5 6 4 0)
       (i-type buffer #x13 5 5 3 1))
      ((equal operation "<")
       (r-type buffer #x33 5 5 6 (if (signed-type-p type) 2 3) 0))
      (t (fail "unsupported RISC-V operation ~A" operation)))
    (unless (member operation '("=" "<") :test #'equal)
      (normalize buffer 5 type))
    (store-slot buffer 5 (lir-instruction-dst instruction))))

(defun outgoing-stack-size (locations)
  (let ((used 0))
    (dolist (location locations)
      (dolist (part (rest location))
        (when (eq (first part) :stack)
          (setf used (max used (+ (second part) 8))))))
    (* 16 (ceiling used 16))))

(defun emit-call (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (name (car (lir-instruction-value instruction)))
         (signature (gethash name (emitter-signatures emitter)))
         (locations (argument-locations (signature-arguments signature)
                                        (emitter-abi-layouts emitter)))
         (stack-size (outgoing-stack-size locations)))
    (stack-adjust buffer stack-size t)
    (loop for slot in (lir-instruction-args instruction)
          for type in (signature-arguments signature)
          for location in locations
          do (move-location buffer slot type location nil))
    (push (make-relocation :offset (length buffer) :name name :kind :call)
          (emitter-relocations emitter))
    (word buffer #x00000097) ; auipc ra, 0
    (i-type buffer #x67 1 1 0 0) ; jalr ra, ra, 0
    (stack-adjust buffer stack-size nil)
    (let ((result (cdr (lir-instruction-value instruction))))
      (unless (eq result :void)
        (move-location buffer (lir-instruction-dst instruction) result
                       (first (argument-locations
                               (list result) (emitter-abi-layouts emitter)))
                       t)))))

(defun emit-data-address (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (name (car (lir-instruction-value instruction)))
         (high-offset (length buffer))
         (label (format nil ".Lpsl_got_~A_~D"
                        (signature-name (emitter-signature emitter))
                        high-offset)))
    (push (cons label high-offset) (emitter-local-labels emitter))
    (push (make-relocation :offset high-offset :name name :kind :rv-got-hi20)
          (emitter-relocations emitter))
    (word buffer #x00000297) ; auipc t0, 0
    (push (make-relocation :offset (length buffer) :name label
                           :kind :rv-pcrel-lo12)
          (emitter-relocations emitter))
    (i-type buffer #x03 5 5 3 0) ; ld t0, 0(t0)
    (store-slot buffer 5 (lir-instruction-dst instruction))))

(defun emit-field-pointer (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (load-slot buffer 5 (first (lir-instruction-args instruction)))
    (load-immediate buffer 6 (lir-instruction-value instruction))
    (r-type buffer #x33 5 5 6 0 0)
    (store-slot buffer 5 (lir-instruction-dst instruction))))

(defun emit-pointer-add (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (arguments (lir-instruction-args instruction)))
    (load-slot buffer 5 (first arguments))
    (load-slot buffer 6 (second arguments))
    (unless (= (lir-instruction-value instruction) 1)
      (load-immediate buffer 28 (lir-instruction-value instruction))
      (r-type buffer #x33 6 6 28 0 1))
    (r-type buffer #x33 5 5 6 0 0)
    (store-slot buffer 5 (lir-instruction-dst instruction))))

(defun emit-unaligned-load (buffer width signed-p)
  (load-immediate buffer 6 0)
  (dotimes (index (/ width 8))
    (i-type buffer #x03 28 5 4 index) ; lbu t3, index(t0)
    (when (plusp index)
      (i-type buffer #x13 28 28 1 (* index 8)))
    (r-type buffer #x33 6 6 28 6 0))
  (when (and signed-p (< width 64))
    (let ((shift (- 64 width)))
      (i-type buffer #x13 6 6 1 shift)
      (i-type buffer #x13 6 6 5 (logior #x400 shift)))))

(defun emit-unaligned-store (buffer width)
  (dotimes (index (/ width 8))
    (when (plusp index)
      (i-type buffer #x13 28 6 5 (* index 8)))
    (s-type buffer #x23 5 (if (zerop index) 6 28) 0 index)))

(defun emit-load (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (type (lir-instruction-value instruction)))
    (load-slot buffer 5 (first (lir-instruction-args instruction)))
    (emit-unaligned-load buffer (scalar-width type) (signed-type-p type))
    (store-slot buffer 6 (lir-instruction-dst instruction))))

(defun emit-store (emitter instruction)
  (let ((buffer (emitter-bytes emitter))
        (arguments (lir-instruction-args instruction))
        (type (lir-instruction-value instruction)))
    (load-slot buffer 5 (first arguments))
    (load-slot buffer 6 (second arguments))
    (emit-unaligned-store buffer (scalar-width type))
    (store-slot buffer 6 (lir-instruction-dst instruction))))

(defun reserve-jump (emitter label)
  (let ((offset (length (emitter-bytes emitter))))
    (push (cons offset label) (emitter-fixups emitter))
    (word (emitter-bytes emitter) (jal-word 0 0))))

(defun emit-branch-zero (emitter instruction)
  (let ((buffer (emitter-bytes emitter)))
    (load-slot buffer 5 (first (lir-instruction-args instruction)))
    (b-type buffer 5 0 1 8) ; bne t0, zero, skip jump
    (reserve-jump emitter (lir-instruction-value instruction))))

(defun emit-label (emitter instruction)
  (let ((label (lir-instruction-value instruction)))
    (when (gethash label (emitter-labels emitter))
      (fail "duplicate RISC-V label ~A" label))
    (setf (gethash label (emitter-labels emitter))
          (length (emitter-bytes emitter)))))

(defun emit-return (emitter instruction)
  (let* ((buffer (emitter-bytes emitter))
         (type (lir-instruction-type instruction)))
    (unless (eq type :void)
      (move-location buffer (first (lir-instruction-args instruction)) type
                     (first (argument-locations
                             (list type) (emitter-abi-layouts emitter)))
                     nil))
    (move-register buffer 2 8)
    (i-type buffer #x03 8 2 3 0)
    (i-type buffer #x03 1 2 3 8)
    (i-type buffer #x13 2 2 0 16)
    (i-type buffer #x67 0 1 0 0)))

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
    (:jump (reserve-jump emitter (lir-instruction-value instruction)))
    (:label (emit-label emitter instruction))
    (:return (emit-return emitter instruction))
    (otherwise (fail "unsupported RISC-V LIR operation ~A"
                     (lir-instruction-op instruction)))))

(defun patch-branches (emitter)
  (dolist (fixup (emitter-fixups emitter))
    (let* ((offset (car fixup))
           (destination (gethash (cdr fixup) (emitter-labels emitter)))
           (delta (and destination (- destination offset))))
      (unless (and destination (evenp delta)
                   (<= (- (ash 1 20)) delta (- (ash 1 20) 2)))
        (fail "RISC-V jump target ~A is missing or out of range"
              (cdr fixup)))
      (patch-word (emitter-bytes emitter) offset (jal-word 0 delta)))))

(defun emit-prologue (buffer frame-size)
  (i-type buffer #x13 2 2 0 -16)
  (s-type buffer #x23 2 1 3 8)
  (s-type buffer #x23 2 8 3 0)
  (move-register buffer 8 2)
  (stack-adjust buffer frame-size t))

(defun compile-function (function contract signatures abi-layouts)
  (unless (and (eq (backend-contract-architecture contract) :riscv64)
               (eq (backend-contract-abi contract) :lp64d))
    (fail "RISC-V64 backend requires LP64D"))
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
     :local-labels (nreverse (emitter-local-labels emitter))
     :frame-size frame-size)))

(defun compile-qemu-virt-startup ()
  (let ((buffer (byte-buffer)))
    (load-immediate buffer 2 #x88000000) ; top of 128 MiB RAM on QEMU virt
    (let ((call-offset (length buffer)))
      (word buffer #x00000097) ; auipc ra, 0
      (i-type buffer #x67 1 1 0 0) ; jalr ra, ra, 0
      (let ((branch-offset (length buffer)))
        (word buffer 0)
        (load-immediate buffer 5 #x5555) ; SiFive test device: success
        (let ((jump-offset (length buffer)))
          (word buffer 0)
          (let ((failure-offset (length buffer)))
            (load-immediate buffer 5 #x13333) ; failure, QEMU exit code 1
            (let ((write-offset (length buffer)))
              (load-immediate buffer 6 #x100000)
              (s-type buffer #x23 6 5 2 0)
              (word buffer #x10500073) ; wfi
              (word buffer (jal-word 0 -4))
              (patch-word buffer branch-offset
                          (b-word 10 0 1 (- failure-offset branch-offset)))
              (patch-word buffer jump-offset
                          (jal-word 0 (- write-offset jump-offset)))
              (make-encoded-function
               :name "_start" :bytes buffer :frame-size 0
               :relocations (list (make-relocation :offset call-offset
                                                  :name "main"
                                                  :kind :call))))))))))
