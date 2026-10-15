(defcstruct word-record
  (bits u64))

(ffi:import-function "next_word_c" ((value word-record)) -> word-record)

(defun roundtrip_word_record (value)
  (declare (type word-record value)
           (returns word-record)
           (c-export :c))
  (ffi:call next_word_c value))
