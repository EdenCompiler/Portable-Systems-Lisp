;; Byte-oriented token scanning for the native compiler bootstrap. The parser
;; will interpret atoms, escapes, and reader dispatch forms in later stages.

(defcstruct psl_scanner
  (data (ptr u8))
  (length usize)
  (cursor usize)
  (error u8))

(defcstruct psl_token
  (kind u32)
  (start usize)
  (length usize))

(defun scanner_has_byte (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (< (deref (field-pointer scanner 'cursor))
         (deref (field-pointer scanner 'length))) 1 0))

(defun scanner_byte_at (scanner offset)
  (declare (type (ptr psl_scanner) scanner)
           (type usize offset)
           (returns u8))
  (deref (pointer+ (deref (field-pointer scanner 'data))
                   (wrap-cast isize offset))))

(defun scanner_peek (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns u8))
  (if (= (scanner_has_byte scanner) 1)
      (scanner_byte_at scanner (deref (field-pointer scanner 'cursor)))
      0))

(defun scanner_advance (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns usize))
  (let ((position (deref (field-pointer scanner 'cursor))))
    (store (field-pointer scanner 'cursor) (wrap+ position 1))))

(defun comment_content_p (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (= (scanner_has_byte scanner) 1)
      (if (= (scanner_peek scanner) 10) 0 1)
      0))

(defun skip_comment (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (while (= (comment_content_p scanner) 1)
    (scanner_advance scanner))
  1)

(defun consume_trivia (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (= (scanner_has_byte scanner) 0)
      0
      (let ((byte (scanner_peek scanner)))
        (if (< byte 33)
            (progn (scanner_advance scanner) 1)
            (if (= byte 59)
                (skip_comment scanner)
                0)))))

(defun skip_trivia (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (while (= (consume_trivia scanner) 1) 1)
  1)

(defun string_content_p (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (= (scanner_has_byte scanner) 0)
      0
      (if (= (scanner_peek scanner) 34) 0 1)))

(defun string_step (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (= (scanner_peek scanner) 92)
      (progn
        (scanner_advance scanner)
        (if (= (scanner_has_byte scanner) 1)
            (progn (scanner_advance scanner) 1)
            0))
      (progn (scanner_advance scanner) 1)))

(defun scan_string (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns u32))
  (scanner_advance scanner)
  (while (= (string_content_p scanner) 1)
    (string_step scanner))
  (if (= (scanner_has_byte scanner) 1)
      (progn (scanner_advance scanner) 7)
      255))

(defun atom_delimiter_p (byte)
  (declare (type u8 byte) (returns c-int))
  (if (< byte 33) 1
      (if (= byte 40) 1
          (if (= byte 41) 1
              (if (= byte 34) 1
                  (if (= byte 59) 1
                      (if (= byte 39) 1
                          (if (= byte 96) 1
                              (if (= byte 44) 1 0)))))))))

(defun bar_content_p (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (= (scanner_has_byte scanner) 0)
      0
      (if (= (scanner_peek scanner) 124) 0 1)))

(defun scan_escaped_byte (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (scanner_advance scanner)
  (if (= (scanner_has_byte scanner) 1)
      (progn (scanner_advance scanner) 1)
      (progn (store (field-pointer scanner 'error) 1) 0)))

(defun scan_bar_step (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (= (scanner_peek scanner) 92)
      (scan_escaped_byte scanner)
      (progn (scanner_advance scanner) 1)))

(defun scan_bar (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (scanner_advance scanner)
  (while (= (bar_content_p scanner) 1)
    (scan_bar_step scanner))
  (if (= (scanner_has_byte scanner) 1)
      (progn (scanner_advance scanner) 1)
      (progn (store (field-pointer scanner 'error) 1) 0)))

(defun atom_content_p (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (if (= (deref (field-pointer scanner 'error)) 1)
      0
      (if (= (scanner_has_byte scanner) 0)
          0
          (if (= (atom_delimiter_p (scanner_peek scanner)) 1) 0 1))))

(defun scan_atom_step (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns c-int))
  (let ((byte (scanner_peek scanner)))
    (if (= byte 124)
        (scan_bar scanner)
        (if (= byte 92)
            (scan_escaped_byte scanner)
            (progn (scanner_advance scanner) 1)))))

(defun scan_atom (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns u32))
  (while (= (atom_content_p scanner) 1)
    (scan_atom_step scanner))
  (if (= (deref (field-pointer scanner 'error)) 1) 255 8))

(defun next_byte_is (scanner byte)
  (declare (type (ptr psl_scanner) scanner)
           (type u8 byte)
           (returns c-int))
  (let ((next (wrap+ (deref (field-pointer scanner 'cursor)) 1)))
    (if (< next (deref (field-pointer scanner 'length)))
        (if (= (scanner_byte_at scanner next) byte) 1 0)
        0)))

(defun scan_punctuation (scanner byte)
  (declare (type (ptr psl_scanner) scanner)
           (type u8 byte)
           (returns u32))
  (cond
    ((= byte 40) (scanner_advance scanner) 1)
    ((= byte 41) (scanner_advance scanner) 2)
    ((= byte 39) (scanner_advance scanner) 3)
    ((= byte 96) (scanner_advance scanner) 4)
    ((= byte 44)
     (scanner_advance scanner)
     (if (= (scanner_peek scanner) 64)
         (progn (scanner_advance scanner) 6)
         5))
    ((= byte 35)
     (if (= (next_byte_is scanner 39) 1)
         (progn (scanner_advance scanner) (scanner_advance scanner) 9)
         0))
    (t 0)))

(defun scan_kind (scanner)
  (declare (type (ptr psl_scanner) scanner) (returns u32))
  (let ((byte (scanner_peek scanner)))
    (if (= byte 34)
        (scan_string scanner)
        (let ((punctuation (scan_punctuation scanner byte)))
          (if (= punctuation 0) (scan_atom scanner) punctuation)))))

(defun finish_token (scanner token start kind)
  (declare (type (ptr psl_scanner) scanner)
           (type (ptr psl_token) token)
           (type usize start)
           (type u32 kind)
           (returns u32))
  (store (field-pointer token 'kind) kind)
  (store (field-pointer token 'start) start)
  (store (field-pointer token 'length)
         (wrap- (deref (field-pointer scanner 'cursor)) start))
  kind)

(defun scan_next (scanner token)
  (declare (type (ptr psl_scanner) scanner)
           (type (ptr psl_token) token)
           (returns u32)
           (c-export :c))
  (skip_trivia scanner)
  (let ((start (deref (field-pointer scanner 'cursor))))
    (if (= (scanner_has_byte scanner) 0)
        (finish_token scanner token start 0)
        (finish_token scanner token start (scan_kind scanner)))))
