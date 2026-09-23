(in-package #:psl.object.elf64)

(defstruct section
  name type flags data (alignment 1) (link 0) (info 0)
  (entry-size 0) (offset 0) (name-index 0))

(defun append-string (buffer string)
  (let ((offset (length buffer)))
    (loop for char across string
          do (unless (< (char-code char) 128)
               (fail "non-ASCII symbol names are not implemented"))
             (emit-byte buffer (char-code char)))
    (emit-byte buffer 0)
    offset))

(defun align-buffer (buffer alignment)
  (loop until (zerop (mod (length buffer) alignment))
        do (emit-byte buffer 0)))

(defun append-buffer (destination source)
  (loop for byte across source do (emit-byte destination byte)))

(defun write-symbol (buffer name info section value size)
  (emit-integer buffer name 4)
  (emit-byte buffer info)
  (emit-byte buffer 0)
  (emit-integer buffer section 2)
  (emit-integer buffer value 8)
  (emit-integer buffer size 8))

(defun collect-text (functions)
  (let ((text (byte-buffer)) (definitions nil) (relocations nil))
    (dolist (function functions)
      (let ((offset (length text)))
        (push (list (encoded-function-name function) offset
                    (length (encoded-function-bytes function)))
              definitions)
        (append-buffer text (encoded-function-bytes function))
        (dolist (relocation (encoded-function-relocations function))
          (push (make-relocation
                 :name (relocation-name relocation)
                 :offset (+ offset (relocation-offset relocation))
                 :kind (relocation-kind relocation))
                relocations))))
    (values text (nreverse definitions) (nreverse relocations))))

(defun collect-data (declarations)
  (let ((bytes (byte-buffer)) (definitions nil) (alignment 1))
    (dolist (declaration declarations)
      (unless (data-declaration-external-p declaration)
        (let ((size (data-declaration-size declaration))
              (field-alignment (data-declaration-alignment declaration)))
          (setf alignment (max alignment field-alignment))
          (align-buffer bytes field-alignment)
          (push (list (data-declaration-name declaration)
                      (length bytes) size)
                definitions)
          (cond
            ((float-type-p (data-declaration-type declaration))
             (emit-integer bytes
                           (float-bits (data-declaration-initial declaration)
                                       (data-declaration-type declaration))
                           size))
            ((or (integer-type-p (data-declaration-type declaration))
                 (pointer-type-p (data-declaration-type declaration)))
             (emit-integer bytes (data-declaration-initial declaration) size))
            (t (dotimes (index size) (emit-byte bytes 0)))))))
    (values bytes (nreverse definitions) alignment)))

(defun external-symbols (signatures data relocations)
  (let ((symbols nil))
    (dolist (relocation relocations)
      (let* ((name (relocation-name relocation))
             (signature (gethash name signatures))
             (declaration (find name data :key #'data-declaration-name
                                :test #'equal)))
        (cond
          ((and signature (signature-external-p signature))
           (push (cons name #x12) symbols))
          ((and declaration (data-declaration-external-p declaration))
           (push (cons name #x11) symbols)))))
    (sort (remove-duplicates symbols :key #'car :test #'equal)
          #'string< :key #'car)))

(defun build-symbol-tables (functions data external)
  (let ((table (byte-buffer))
        (names (byte-buffer))
        (indices (make-hash-table :test #'equal)))
    (emit-byte names 0)
    (write-symbol table 0 0 0 0 0)
    (write-symbol table 0 3 1 0 0) ; local .text section symbol
    (write-symbol table 0 3 2 0 0) ; local .data section symbol
    (loop for (name offset size) in functions
          for index from 3
          do (setf (gethash name indices) index)
             (write-symbol table (append-string names name) #x12 1 offset size))
    (loop for (name offset size) in data
          for index from (+ 3 (length functions))
          do (setf (gethash name indices) index)
             (write-symbol table (append-string names name) #x11 2 offset size))
    (loop for (name . info) in external
          for index from (+ 3 (length functions) (length data))
          do (setf (gethash name indices) index)
             (write-symbol table (append-string names name) info 0 0 0))
    (values table names indices)))

(defun build-relocations (relocations symbol-indices contract)
  (let ((table (byte-buffer)))
    (dolist (relocation relocations)
      (let ((index (gethash (relocation-name relocation) symbol-indices)))
        (unless index
          (fail "internal error: missing symbol ~A" (relocation-name relocation)))
        (emit-integer table (relocation-offset relocation) 8)
        (emit-integer table
                      (+ (ash index 32)
                         (ecase (relocation-kind relocation)
                           (:call (backend-contract-call-relocation contract))
                           (:got 9))) 8)
        (emit-integer table -4 8)))
    table))

(defun make-sections (text data data-alignment rela symbols names)
  (let ((section-names (byte-buffer)))
    (emit-byte section-names 0)
    (let ((sections
            (list (make-section :name ".text" :type 1 :flags 6
                                :data text :alignment 16)
                  (make-section :name ".data" :type 1 :flags 3
                                :data data :alignment data-alignment)
                  (make-section :name ".rela.text" :type 4 :flags 0
                                :data rela :alignment 8 :link 4 :info 1
                                :entry-size 24)
                  (make-section :name ".symtab" :type 2 :flags 0
                                :data symbols :alignment 8 :link 5 :info 3
                                :entry-size 24)
                  (make-section :name ".strtab" :type 3 :flags 0 :data names)
                  (make-section :name ".shstrtab" :type 3 :flags 0
                                :data section-names)
                  (make-section :name ".note.GNU-stack" :type 1 :flags 0
                                :data (byte-buffer)))))
      (dolist (section sections)
        (setf (section-name-index section)
              (append-string section-names (section-name section))))
      sections)))

(defun append-section-data (object sections)
  (dolist (section sections)
    (align-buffer object (section-alignment section))
    (setf (section-offset section) (length object))
    (append-buffer object (section-data section))))

(defun write-section-header (object section)
  (emit-integer object (section-name-index section) 4)
  (emit-integer object (section-type section) 4)
  (emit-integer object (section-flags section) 8)
  (emit-integer object 0 8) ; relocatable sections have no memory address
  (emit-integer object (section-offset section) 8)
  (emit-integer object (length (section-data section)) 8)
  (emit-integer object (section-link section) 4)
  (emit-integer object (section-info section) 4)
  (emit-integer object (section-alignment section) 8)
  (emit-integer object (section-entry-size section) 8))

(defun patch-integer (buffer offset value count)
  (dotimes (i count)
    (setf (aref buffer (+ offset i)) (ldb (byte 8 (* i 8)) value))))

(defun write-elf-header (object section-offset section-count contract)
  (setf (aref object 0) #x7f (aref object 1) #x45
        (aref object 2) #x4c (aref object 3) #x46
        (aref object 4) 2 (aref object 5) 1 (aref object 6) 1)
  (patch-integer object 16 1 2)  ; ET_REL
  (patch-integer object 18 (backend-contract-elf-machine contract) 2)
  (patch-integer object 20 1 4)
  (patch-integer object 40 section-offset 8)
  (patch-integer object 52 64 2)
  (patch-integer object 58 64 2)
  (patch-integer object 60 section-count 2)
  (patch-integer object 62 6 2)) ; .shstrtab section index

(defun assemble-object (sections contract)
  (let ((object (byte-buffer)))
    (dotimes (i 64) (emit-byte object 0))
    (append-section-data object sections)
    (align-buffer object 8)
    (let ((section-offset (length object)))
      (dotimes (i 64) (emit-byte object 0)) ; null section header
      (dolist (section sections) (write-section-header object section))
      (write-elf-header object section-offset (1+ (length sections))
                        contract))
    object))

(defun write-object-file (bytes output)
  (with-open-file (stream output :direction :output :if-exists :supersede
                          :element-type '(unsigned-byte 8))
    (write-sequence bytes stream))
  output)

(defun write-elf-object (functions signatures data contract output)
  (unless (and (eq (backend-contract-object-format contract) :elf64)
               (eq (backend-contract-endianness contract) :little))
    (fail "ELF64 writer needs a little-endian ELF64 target"))
  (multiple-value-bind (text function-definitions relocations)
      (collect-text functions)
    (multiple-value-bind (data-bytes data-definitions data-alignment)
        (collect-data data)
      (multiple-value-bind (symbols names indices)
          (build-symbol-tables
           function-definitions data-definitions
           (external-symbols signatures data relocations))
        (let* ((rela (build-relocations relocations indices contract))
               (sections (make-sections text data-bytes data-alignment
                                        rela symbols names)))
          (write-object-file (assemble-object sections contract) output))))))
