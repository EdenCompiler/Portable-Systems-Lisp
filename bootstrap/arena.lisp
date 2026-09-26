;; Caller-provided storage for native compiler objects. The base address must
;; satisfy the largest alignment requested by this arena's users.

(defcstruct psl_arena
  (data (ptr u8))
  (used usize)
  (capacity usize))

(defun arena_valid_alignment (alignment)
  (declare (type usize alignment) (returns c-int))
  (if (= alignment 0)
      0
      (if (= (bits-and alignment (wrap- alignment 1)) 0) 1 0)))

(defun arena_fit (arena padding size)
  (declare (type (ptr psl_arena) arena)
           (type usize padding size)
           (returns c-int))
  (let ((used (deref (field-pointer arena 'used)))
        (capacity (deref (field-pointer arena 'capacity))))
    (if (< capacity used)
        0
        (let ((available (wrap- capacity used)))
          (if (< available padding)
              0
              (if (< (wrap- available padding) size) 0 1))))))

(defun arena_alloc (arena size alignment)
  (declare (type (ptr psl_arena) arena)
           (type usize size alignment)
           (returns (ptr u8))
           (c-export :c))
  (if (= (arena_valid_alignment alignment) 0)
      (ptr-from-address (ptr u8) 0)
      (let ((used (deref (field-pointer arena 'used)))
            (mask (wrap- alignment 1)))
        (let ((padding (bits-and (wrap- 0 used) mask)))
          (if (= (arena_fit arena padding size) 0)
              (ptr-from-address (ptr u8) 0)
              (let ((start (wrap+ used padding)))
                (store (field-pointer arena 'used) (wrap+ start size))
                (pointer+ (deref (field-pointer arena 'data))
                          (wrap-cast isize start))))))))
