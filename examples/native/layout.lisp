(defstruct/packed packet
  (tag u8)
  (count u16)
  (payload u32))

(defun main ()
  (declare (returns c-int) (c-export :c))
  (let ((payload-offset (offset-of 'packet 'payload))
        (packet-size (sizeof 'packet)))
    (if (= (alignof 'packet) 1)
        (if (= (wrap+ payload-offset 4) packet-size) 0 1)
        1)))
