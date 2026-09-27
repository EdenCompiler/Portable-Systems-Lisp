(defcstruct query_inner (byte u8) (word u32))
(defcstruct query_outer (tag u8) (inner query_inner) (memory (ptr void)))

(defun query_inner_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'query_inner))

(defun query_outer_size ()
  (declare (returns usize) (c-export :c))
  (sizeof (quote query_outer)))

(defun query_outer_alignment ()
  (declare (returns usize) (c-export :c))
  (alignof 'query_outer))

(defun query_inner_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of 'query_outer 'inner))

(defun query_memory_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of (quote query_outer) (quote memory)))

(defun query_pointer_size ()
  (declare (returns usize) (c-export :c))
  (sizeof '(ptr void)))

(defun query_scalar_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'u16))

(defun pointer_address (memory)
  (declare (type (ptr u8) memory) (returns usize) (c-export :c))
  (ptr-address memory))

(defun opaque_address (memory)
  (declare (type (ptr void) memory) (returns usize) (c-export :c))
  (ptr-address memory))

(defun address_roundtrip (address)
  (declare (type usize address) (returns usize) (c-export :c))
  (ptr-address (ptr-cast (ptr void) (ptr-from-address (ptr u8) address))))

(defun pointer_check (memory)
  (declare (type (ptr void) memory) (returns u64) (c-export :c))
  (if memory
      (if (= (ptr-address memory) 0) 42 43)
      0))
