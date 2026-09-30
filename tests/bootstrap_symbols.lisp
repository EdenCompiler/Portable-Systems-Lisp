(defcstruct MIXED-BOX (PAYLOAD-VALUE U64))

(DEFUN HELPER-ONE (Some-Value)
  (DECLARE (TYPE U64 SOME-VALUE) (RETURNS U64))
  (PSL:WRAP+ some-value 17))

(DEFUN ANSWER ()
  (DECLARE (RETURNS U64) (C-EXPORT :C))
  (LET ((LOCAL-VALUE (helper-one 25)))
    (IF (= local-value 42)
        local-value
        0)))

(DEFUN MIXED_BOX_SIZE ()
  (DECLARE (RETURNS USIZE) (C-EXPORT :C))
  (SIZEOF 'mixed-box))

(DEFUN MIXED_BOX_PAYLOAD_OFFSET ()
  (DECLARE (RETURNS USIZE) (C-EXPORT :C))
  (OFFSET-OF 'MIXED-BOX 'payload-value))
