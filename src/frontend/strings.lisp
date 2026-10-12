(in-package #:psl.frontend)

(defun next-string-name (context)
  (prog1 (format nil "%psl-string-~D"
                 (analysis-context-string-counter context))
    (incf (analysis-context-string-counter context))))

(defun nul-terminated-utf8 (text)
  (let* ((encoded (sb-ext:string-to-octets text :external-format :utf-8))
         (bytes (make-array (1+ (length encoded))
                            :element-type '(unsigned-byte 8)
                            :initial-element 0)))
    (replace bytes encoded)
    bytes))

(defun analyze-c-string (form context expected)
  (unless (and (= (length form) 2) (stringp (second form)))
    (fail "FFI:C-STRING requires one string literal"))
  (unless (equal expected '(:ptr :u8 nil nil))
    (fail "FFI:C-STRING requires an expected (PTR U8) type"))
  (let* ((bytes (nul-terminated-utf8 (second form)))
         (name (next-string-name context)))
    (push (make-data-declaration
           :name name :type :u8 :size (length bytes) :alignment 1
           :initial bytes :external-p nil :local-p t)
          (analysis-context-data context))
    (make-hir :kind :data-address :type '(:ptr :u8 nil nil)
              :value (cons name :u8))))

(defun analyze-string-literal (text context expected)
  (require-hosted-runtime context)
  (when (and expected (not (eq expected :value)))
    (fail "string literal cannot have machine type ~A" expected))
  (let* ((bytes (nul-terminated-utf8 text))
         (name (next-string-name context))
         (address (make-hir :kind :data-address :type '(:ptr :u8 nil nil)
                            :value (cons name :u8))))
    (push (make-data-declaration
           :name name :type :u8 :size (length bytes) :alignment 1
           :initial bytes :external-p nil :local-p t)
          (analysis-context-data context))
    (runtime-call-node
     "psl_rt_make_string_from_bytes" '((:ptr :u8 nil nil) :usize)
     :value :string :allocates
     (list address (make-hir :kind :literal :type :usize
                            :value (1- (length bytes))))
     context)))
