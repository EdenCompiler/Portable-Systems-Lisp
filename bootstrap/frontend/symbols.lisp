;; Native source spelling is independent of target and linker spelling.
;; Ordinary ASCII reader tokens fold case; escaped symbols and user packages
;; remain outside this subset. Qualified builtins keep their package owner.
(defun source_fold_byte (byte)
  (declare (type u8 byte) (returns u8))
  (if (< 64 byte)
      (if (< byte 91) (wrap+ byte 32) byte)
      byte))

(defun source_bytes_match (source start bits count)
  (declare (type (ptr u8) source) (type usize start count)
           (type u64 bits) (returns c-int))
  (if (= count 0) 1
      (if (= (source_fold_byte (deref (pointer+ source (wrap-cast isize start))))
             (wrap-cast u8 bits))
          (source_bytes_match source (wrap+ start 1) (shr64 bits 8)
                              (wrap- count 1))
          0)))

(defun source_same_name_p (left right remaining)
  (declare (type (ptr u8) left right) (type usize remaining) (returns c-int))
  (if (= remaining 0) 1
      (if (= (source_fold_byte (deref left)) (source_fold_byte (deref right)))
          (source_same_name_p (pointer+ left 1) (pointer+ right 1)
                              (wrap- remaining 1))
          0)))

(defun source_exact_name_p (left right remaining)
  (declare (type (ptr u8) left right) (type usize remaining) (returns c-int))
  (if (= remaining 0) 1
      (if (= (deref left) (deref right))
          (source_exact_name_p (pointer+ left 1) (pointer+ right 1)
                               (wrap- remaining 1))
          0)))

(defun source_folded_bits_match (left right remaining)
  (declare (type u64 left right) (type usize remaining) (returns c-int))
  (if (= remaining 0) 1
      (if (= (source_fold_byte (wrap-cast u8 left)) (wrap-cast u8 right))
          (source_folded_bits_match (shr64 left 8) (shr64 right 8)
                                    (wrap- remaining 1))
          0)))

(defun source_identifier_byte_p (byte first)
  (declare (type u8 byte first) (returns c-int))
  (let ((folded (source_fold_byte byte)))
    (cond
      ((= folded 95) 1)
      ((= folded 45) (if (= first 1) 0 1))
      ((< 96 folded) (if (< folded 123) 1 0))
      ((= first 1) 0)
      ((< 47 folded) (if (< folded 58) 1 0))
      (t 0))))

(defun source_identifier_from (source start length index)
  (declare (type (ptr u8) source) (type usize start length index)
           (returns c-int))
  (if (= index length) 1
      (let ((byte (deref (pointer+ source (wrap-cast isize (wrap+ start index))))))
        (if (= (source_identifier_byte_p byte (if (= index 0) 1 0)) 1)
            (source_identifier_from source start length (wrap+ index 1))
            0))))

(defun source_simple_identifier_p (source start length)
  (declare (type (ptr u8) source) (type usize start length) (returns c-int))
  (if (= length 0) 0
      (if (< 255 length) 0
          (source_identifier_from source start length 0))))

(defun source_foreign_name_p (source foreign remaining)
  (declare (type (ptr u8) source foreign) (type usize remaining) (returns c-int))
  (if (= remaining 0) 1
      (if (= (source_fold_byte (deref source)) (deref foreign))
          (source_foreign_name_p (pointer+ source 1) (pointer+ foreign 1)
                                 (wrap- remaining 1))
          0)))

(defun source_builtin_package (bits length)
  (declare (type u64 bits) (type usize length) (returns u8))
  (cond
    ((= (source_fold_byte (wrap-cast u8 bits)) 58) 0) ; keywords have their own package
    ((= (source_folded_bits_match bits #x3e2d 2) 1) 0) ; FFI signature arrow
    ((= (source_folded_bits_match bits #x3d 1) 1) 1) ; =
    ((= (source_folded_bits_match bits #x3c 1) 1) 1) ; <
    ((= (source_folded_bits_match bits #x74 1) 1) 1) ; t
    ((= (source_folded_bits_match bits #x6c696e 3) 1) 1) ; nil
    ((= (source_folded_bits_match bits #x6e75666564 5) 1) 1) ; defun
    ((= (source_folded_bits_match bits #x6572616c636564 7) 1) 1) ; declare
    ((= (source_folded_bits_match bits #x65707974 4) 1) 1) ; type
    ((= (source_folded_bits_match bits #x74726f707865 6) 1) 1) ; export
    ((= (source_folded_bits_match bits #x6669 2) 1) 1) ; if
    ((= (source_folded_bits_match bits #x6e676f7270 5) 1) 1) ; progn
    ((= (source_folded_bits_match bits #x74656c 3) 1) 1) ; let
    ((= (source_folded_bits_match bits #x646e6f63 4) 1) 1) ; cond
    ((= (source_folded_bits_match bits #x65746f7571 5) 1) 1) ; quote
    ((= (bits-and bits #xffffffff) #x3a696666) 0) ; explicit ffi:
    (t 2)))

(defun source_builtin_offset (source start actual expected package)
  (declare (type (ptr u8) source) (type usize start actual expected)
           (type u8 package) (returns usize))
  (cond
    ((= actual expected) 1) ; one-based offset, zero means no match
    ((= package 1)
     (if (= actual (wrap+ expected 3))
         (if (= (source_bytes_match source start #x3a6c63 3) 1) 4 0)
         0))
    ((= package 2)
     (if (= actual (wrap+ expected 4))
         (if (= (source_bytes_match source start #x3a6c7370 4) 1) 5 0)
         0))
    (t 0)))

(defun source_builtin_word_p (source start actual first last expected)
  (declare (type (ptr u8) source) (type usize start actual expected)
           (type u64 first last) (returns c-int))
  (let ((offset (source_builtin_offset source start actual expected
                 (source_builtin_package first expected))))
    (if (= offset 0) 0
        (let ((name (wrap+ start (wrap- offset 1))))
          (if (< expected 9)
              (source_bytes_match source name first expected)
              (if (= (source_bytes_match source name first 8) 1)
                  (source_bytes_match source (wrap+ name 8) last
                                      (wrap- expected 8))
                  0))))))
