(defcstruct qualified_cell
  (value u16)
  (next (ptr u8 :const :volatile)))

(defcstruct qualified_outer
  (cell qualified_cell))

(ffi:import-function "qualifier_observe" ((value u16)) -> void)
(ffi:import-function "qualifier_update" ((pointer (ptr u16 :volatile))) -> void)

(defun qualifier_identity (pointer)
  (declare (type (ptr u8 :volatile :const) pointer)
           (returns (ptr u8 :const :volatile)))
  (if t pointer pointer))

(defun qualifier_read (pointer offset)
  (declare (type (ptr u8 :const) pointer) (type isize offset)
           (returns u8) (c-export :c))
  (deref (pointer+ pointer offset)))

(defun qualifier_chain (slot)
  (declare (type (ptr (ptr u8 :const :volatile) :const) slot)
           (returns (ptr u8 :volatile :const)) (c-export :c))
  (qualifier_identity (deref slot)))

(defun qualifier_fields (outer)
  (declare (type (ptr qualified_outer :volatile :const) outer)
           (returns u16) (c-export :c))
  (let ((cell (field-pointer outer 'cell)))
    (wrap+ (deref (field-pointer cell 'value))
           (wrap-cast u16 (deref (qualifier_identity
                                 (deref (field-pointer cell 'next))))))))

(defun qualifier_writes (pointer)
  (declare (type (ptr u16 :volatile) pointer)
           (returns u16) (c-export :c))
  (ffi:call qualifier_observe (deref pointer))
  (store pointer 65535)
  (ffi:call qualifier_observe (deref pointer))
  (ffi:call qualifier_update pointer)
  (deref pointer))

(defun qualifier_discarded_read (pointer)
  (declare (type (ptr u16 :const :volatile) pointer)
           (returns u16) (c-export :c))
  (deref pointer)
  (ffi:call qualifier_update (ptr-cast (ptr u16 :volatile) pointer))
  (deref pointer))

(defun qualifier_cast_store (pointer value)
  (declare (type (ptr u8 :const) pointer) (type u8 value)
           (returns u8) (c-export :c))
  (store (ptr-cast (ptr u8 :volatile) pointer) value))

(defun qualifier_null ()
  (declare (returns c-int) (c-export :c))
  (if (ptr-from-address (ptr u8 :volatile :const) 0) 1 0))

(defun qualifier_from_bits (bits)
  (declare (type usize bits) (returns (ptr u8 :const :volatile))
           (c-export :c))
  (ptr-from-address (ptr u8 :volatile :const) bits))
