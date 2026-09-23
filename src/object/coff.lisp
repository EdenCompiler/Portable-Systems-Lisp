(in-package #:psl.object.coff)

(defstruct coff-section name bytes flags (relocations nil)
           (data-offset 0) (relocation-offset 0))
(defstruct coff-symbol name value section type storage)
(defstruct coff-relocation offset name type)

(defun coff-append-buffer (destination source)
  (loop for byte across source do (emit-byte destination byte)))

(defun coff-align (buffer alignment)
  (loop until (zerop (mod (length buffer) alignment))
        do (emit-byte buffer 0)))

(defun coff-ascii (buffer name)
  (loop for character across name
        for code = (char-code character)
        do (unless (< code 128)
             (fail "non-ASCII COFF symbol names are not implemented"))
           (emit-byte buffer code)))

(defun coff-text (functions)
  (let ((bytes (byte-buffer)) (definitions nil) (relocations nil))
    (dolist (function functions)
      (let ((offset (length bytes)))
        (push (list (encoded-function-name function) offset
                    (length (encoded-function-bytes function)))
              definitions)
        (coff-append-buffer bytes (encoded-function-bytes function))
        (dolist (relocation (encoded-function-relocations function))
          (unless (member (relocation-kind relocation) '(:call :data))
            (fail "unsupported COFF relocation kind ~A"
                  (relocation-kind relocation)))
          (push (make-coff-relocation
                 :offset (+ offset (relocation-offset relocation))
                 :name (relocation-name relocation) :type 4)
                relocations))))
    (values bytes (nreverse definitions) (nreverse relocations))))

(defun coff-data (declarations)
  (let ((bytes (byte-buffer)) (definitions nil))
    (dolist (declaration declarations)
      (unless (data-declaration-external-p declaration)
        (coff-align bytes (data-declaration-alignment declaration))
        (let ((size (data-declaration-size declaration)))
          (push (list (data-declaration-name declaration)
                      (length bytes) size)
                definitions)
          (cond
            ((float-type-p (data-declaration-type declaration))
             (emit-integer bytes
                           (float-bits (data-declaration-initial declaration)
                                       (data-declaration-type declaration)) size))
            ((or (integer-type-p (data-declaration-type declaration))
                 (pointer-type-p (data-declaration-type declaration)))
             (emit-integer bytes (data-declaration-initial declaration) size))
            (t (dotimes (index size) (emit-byte bytes 0)))))))
    (values bytes (nreverse definitions))))

(defun coff-unwind-info (frame-size)
  (let ((bytes (byte-buffer))
        (allocation-slots (cond ((zerop frame-size) 0)
                                ((<= frame-size 128) 1)
                                ((<= frame-size 524280) 2)
                                (t (fail "Windows stack frame is too large")))))
    (emit-bytes bytes 1 11 (+ allocation-slots 2) 5)
    (cond
      ((= allocation-slots 1)
       (emit-bytes bytes 11 (+ #x20 (1- (/ frame-size 8)))))
      ((= allocation-slots 2)
       (emit-bytes bytes 11 1)
       (emit-integer bytes (/ frame-size 8) 2)))
    (emit-bytes bytes 4 3 1 #x50)
    (coff-align bytes 4)
    bytes))

(defun coff-unwind-sections (functions definitions)
  (let ((pdata (byte-buffer)) (xdata (byte-buffer)) (relocations nil))
    (loop for function in functions
          for definition in definitions
          for name = (first definition)
          for size = (third definition)
          do (coff-align xdata 4)
             (let ((entry-offset (length pdata))
                   (unwind-offset (length xdata)))
               (emit-integer pdata 0 4)
               (emit-integer pdata size 4)
               (emit-integer pdata unwind-offset 4)
               (push (make-coff-relocation
                      :offset entry-offset :name name :type 3)
                     relocations)
               (push (make-coff-relocation
                      :offset (+ entry-offset 4) :name name :type 3)
                     relocations)
               (push (make-coff-relocation
                      :offset (+ entry-offset 8) :name ".xdata" :type 3)
                     relocations)
               (coff-append-buffer xdata
                                   (coff-unwind-info
                                    (encoded-function-frame-size function)))))
    (values pdata xdata (nreverse relocations))))

(defun coff-add-symbol (symbols indices name value section type storage)
  (unless (gethash name indices)
    (setf (gethash name indices) (length symbols))
    (vector-push-extend
     (make-coff-symbol :name name :value value :section section
                       :type type :storage storage)
     symbols)))

(defun coff-symbols (definitions data-definitions signatures relocations)
  (let ((symbols (make-array 0 :adjustable t :fill-pointer 0))
        (indices (make-hash-table :test #'equal)))
    (loop for name in '(".text" ".data" ".pdata" ".xdata")
          for section from 1
          do (coff-add-symbol symbols indices name 0 section 0 3))
    (dolist (definition definitions)
      (destructuring-bind (name offset size) definition
        (declare (ignore size))
        (let ((signature (gethash name signatures)))
          (coff-add-symbol symbols indices name offset 1 #x20
                           (if (signature-local-p signature) 3 2)))))
    (dolist (definition data-definitions)
      (destructuring-bind (name offset size) definition
        (declare (ignore size))
        (coff-add-symbol symbols indices name offset 2 0 2)))
    (dolist (relocation relocations)
      (let ((name (coff-relocation-name relocation)))
        (unless (gethash name indices)
          (coff-add-symbol symbols indices name 0 0
                           (if (gethash name signatures) #x20 0) 2))))
    (values symbols indices)))

(defun coff-write-name (buffer strings name)
  (if (<= (length name) 8)
      (progn
        (coff-ascii buffer name)
        (dotimes (index (- 8 (length name))) (emit-byte buffer 0)))
      (progn
        (emit-integer buffer 0 4)
        (emit-integer buffer (length strings) 4)
        (coff-ascii strings name)
        (emit-byte strings 0))))

(defun coff-write-symbols (symbols)
  (let ((bytes (byte-buffer)) (strings (byte-buffer)))
    (dotimes (index 4) (emit-byte strings 0))
    (loop for symbol across symbols
          do (coff-write-name bytes strings (coff-symbol-name symbol))
             (emit-integer bytes (coff-symbol-value symbol) 4)
             (emit-integer bytes (coff-symbol-section symbol) 2)
             (emit-integer bytes (coff-symbol-type symbol) 2)
             (emit-byte bytes (coff-symbol-storage symbol))
             (emit-byte bytes 0))
    (patch-i32 strings 0 (length strings))
    (values bytes strings)))

(defun coff-write-relocations (section indices)
  (let ((bytes (byte-buffer)))
    (dolist (relocation (coff-section-relocations section))
      (let ((index (gethash (coff-relocation-name relocation) indices)))
        (unless index
          (fail "missing COFF symbol ~A" (coff-relocation-name relocation)))
        (emit-integer bytes (coff-relocation-offset relocation) 4)
        (emit-integer bytes index 4)
        (emit-integer bytes (coff-relocation-type relocation) 2)))
    bytes))

(defun coff-write-section-header (buffer section)
  (when (> (length (coff-section-relocations section)) #xffff)
    (fail "COFF section ~A has too many relocations"
          (coff-section-name section)))
  (coff-ascii buffer (coff-section-name section))
  (dotimes (index (- 8 (length (coff-section-name section))))
    (emit-byte buffer 0))
  (emit-integer buffer 0 8)
  (emit-integer buffer (length (coff-section-bytes section)) 4)
  (emit-integer buffer (coff-section-data-offset section) 4)
  (emit-integer buffer (coff-section-relocation-offset section) 4)
  (emit-integer buffer 0 4)
  (emit-integer buffer (length (coff-section-relocations section)) 2)
  (emit-integer buffer 0 2)
  (emit-integer buffer (coff-section-flags section) 4))

(defun coff-write-header (buffer sections symbols symbol-offset)
  (emit-integer buffer #x8664 2)
  (emit-integer buffer (length sections) 2)
  (emit-integer buffer 0 4)
  (emit-integer buffer symbol-offset 4)
  (emit-integer buffer (length symbols) 4)
  (emit-integer buffer 0 2)
  (emit-integer buffer 0 2))

(defun coff-assemble (sections symbols indices)
  (let ((buffer (byte-buffer)))
    (dotimes (index (+ 20 (* 40 (length sections)))) (emit-byte buffer 0))
    (dolist (section sections)
      (coff-align buffer 4)
      (setf (coff-section-data-offset section) (length buffer))
      (coff-append-buffer buffer (coff-section-bytes section)))
    (dolist (section sections)
      (let ((bytes (coff-write-relocations section indices)))
        (when (plusp (length bytes))
          (coff-align buffer 4)
          (setf (coff-section-relocation-offset section) (length buffer))
          (coff-append-buffer buffer bytes))))
    (coff-align buffer 4)
    (let ((symbol-offset (length buffer)))
      (multiple-value-bind (symbol-bytes strings) (coff-write-symbols symbols)
        (coff-append-buffer buffer symbol-bytes)
        (coff-append-buffer buffer strings))
      (let ((header (byte-buffer)))
        (coff-write-header header sections symbols symbol-offset)
        (dolist (section sections)
          (coff-write-section-header header section))
        (replace buffer header :start1 0)))
    buffer))

(defun write-coff-object (functions signatures data contract output)
  (unless (and (eq (backend-contract-object-format contract) :coff)
               (eq (backend-contract-endianness contract) :little))
    (fail "COFF writer requires a little-endian COFF target"))
  (multiple-value-bind (text definitions text-relocations)
      (coff-text functions)
    (multiple-value-bind (data-bytes data-definitions) (coff-data data)
      (multiple-value-bind (pdata xdata pdata-relocations)
          (coff-unwind-sections functions definitions)
        (let* ((sections
                 (list (make-coff-section :name ".text" :bytes text
                                          :flags #x60500020
                                          :relocations text-relocations)
                       (make-coff-section :name ".data" :bytes data-bytes
                                          :flags #xc0500040)
                       (make-coff-section :name ".pdata" :bytes pdata
                                          :flags #x40300040
                                          :relocations pdata-relocations)
                       (make-coff-section :name ".xdata" :bytes xdata
                                          :flags #x40300040)))
               (all-relocations (append text-relocations pdata-relocations)))
          (multiple-value-bind (symbols indices)
              (coff-symbols definitions data-definitions signatures
                            all-relocations)
            (with-open-file (stream output :direction :output
                                    :if-exists :supersede
                                    :element-type '(unsigned-byte 8))
              (write-sequence (coff-assemble sections symbols indices)
                              stream)))))))
  output)
