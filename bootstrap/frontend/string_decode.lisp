;; Validate the raw UTF-8 source before removing Lisp backslash escapes.
(defun native_literal_utf8_start (scan byte)
  (declare (type (ptr native_literal_scan) scan) (type u8 byte) (returns c-int))
  (cond
    ((< byte 128) 1)
    ((< byte 194) 0)
    ((< byte 224) (progn (store (field-pointer scan 'pending) 1) 1))
    ((< byte 240)
     (progn
       (store (field-pointer scan 'pending) 2)
       (if (= byte 224) (store (field-pointer scan 'minimum) 160) (wrap-cast u8 0))
       (if (= byte 237) (store (field-pointer scan 'maximum) 159) (wrap-cast u8 0)) 1))
    ((< byte 245)
     (progn
       (store (field-pointer scan 'pending) 3)
       (if (= byte 240) (store (field-pointer scan 'minimum) 144) (wrap-cast u8 0))
       (if (= byte 244) (store (field-pointer scan 'maximum) 143) (wrap-cast u8 0)) 1))
    (t 0)))

(defun native_literal_utf8_byte (scan byte)
  (declare (type (ptr native_literal_scan) scan) (type u8 byte) (returns c-int))
  (if (= (deref (field-pointer scan 'pending)) 0)
      (native_literal_utf8_start scan byte)
      (if (< byte (deref (field-pointer scan 'minimum))) 0
          (if (< (deref (field-pointer scan 'maximum)) byte) 0
              (progn
                (store (field-pointer scan 'pending) (wrap- (deref (field-pointer scan 'pending)) 1))
                (store (field-pointer scan 'minimum) 128)
                (store (field-pointer scan 'maximum) 191) 1)))))

(defun native_literal_decode_byte (scan byte)
  (declare (type (ptr native_literal_scan) scan) (type u8 byte) (returns c-int))
  (if (= (native_literal_utf8_byte scan byte) 0) 0
      (if (if (= byte 92) (= (deref (field-pointer scan 'quoted)) 0) nil)
          (progn (store (field-pointer scan 'quoted) 1) 1)
          (let ((output (deref (field-pointer scan 'output)))
                (count (deref (field-pointer scan 'count))))
            (if (= (ptr-address output) 0) (wrap-cast u8 0)
                (store (pointer+ output (wrap-cast isize count)) byte))
            (store (field-pointer scan 'count) (wrap+ count 1))
            (store (field-pointer scan 'quoted) 0) 1))))

(defun native_literal_scan_init (context body output)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (type (ptr u8) output) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (scan (field-pointer context 'literal_scan)))
    (let ((node (parser_node parser body)))
      (let ((start (deref (field-pointer node 'start)))
            (length (deref (field-pointer node 'length)))
            (available (deref (field-pointer (deref (field-pointer parser 'scanner)) 'length))))
        (if (< length 2) 0
            (if (< available start) 0
                (if (< (wrap- available start) length) 0
                    (progn
                      (store (field-pointer scan 'cursor) (wrap+ start 1))
                      (store (field-pointer scan 'end) (wrap- (wrap+ start length) 1))
                      (store (field-pointer scan 'count) 0)
                      (store (field-pointer scan 'output) output)
                      (store (field-pointer scan 'pending) 0)
                      (store (field-pointer scan 'minimum) 128)
                      (store (field-pointer scan 'maximum) 191)
                      (store (field-pointer scan 'quoted) 0)
                      (store (field-pointer scan 'valid) 1) 1))))))))

(defun native_literal_scan_finish (scan)
  (declare (type (ptr native_literal_scan) scan) (returns usize))
  (if (= (deref (field-pointer scan 'valid)) 0) 0
      (if (= (deref (field-pointer scan 'quoted)) 1) 0
          (if (< 0 (deref (field-pointer scan 'pending))) 0
              (let ((count (deref (field-pointer scan 'count)))
                    (output (deref (field-pointer scan 'output))))
                (if (= (ptr-address output) 0) (wrap-cast u8 0)
                    (store (pointer+ output (wrap-cast isize count)) 0))
                (wrap+ count 1))))))

(defun native_literal_decode (context body output)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (type (ptr u8) output) (returns usize))
  (if (= (native_literal_scan_init context body output) 0) 0
      (let ((scan (field-pointer context 'literal_scan))
            (source (deref (field-pointer context 'source))))
        (while (if (= (deref (field-pointer scan 'valid)) 1)
                   (< (deref (field-pointer scan 'cursor)) (deref (field-pointer scan 'end))) nil)
          (if (= (native_literal_decode_byte scan
                  (deref (pointer+ source (wrap-cast isize (deref (field-pointer scan 'cursor)))))) 0)
              (store (field-pointer scan 'valid) 0) (wrap-cast u8 0))
          (store (field-pointer scan 'cursor) (wrap+ (deref (field-pointer scan 'cursor)) 1)))
        (native_literal_scan_finish scan))))
