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

(defun string-byte-write-node (name index byte context)
  (runtime-call-node
   "psl_rt_string_set_byte" '(:value :usize :u8) :void :string :none
   (list (make-hir :kind :variable :type :value :value name)
         (make-hir :kind :literal :type :usize :value index)
         (make-hir :kind :literal :type :u8 :value byte))
   context))

(defun analyze-string-literal (text context expected)
  (require-hosted-runtime context)
  (when (and expected (not (eq expected :value)))
    (fail "string literal cannot have machine type ~A" expected))
  (let* ((bytes (sb-ext:string-to-octets text :external-format :utf-8))
         (name (next-string-name context))
         (initializer
           (runtime-call-node
            "psl_rt_make_string" '(:usize :u8) :value :string :allocates
            (list (make-hir :kind :literal :type :usize
                            :value (length bytes))
                  (make-hir :kind :literal :type :u8 :value 0))
            context))
         (writes (loop for byte across bytes
                       for index from 0
                       collect (string-byte-write-node name index byte context)))
         (result (make-hir :kind :variable :type :value :value name))
         (body (make-hir :kind :progn :type :value
                         :children (append writes (list result)))))
    (make-hir :kind :let :type :value
              :value (list (cons name initializer))
              :children (list body))))
