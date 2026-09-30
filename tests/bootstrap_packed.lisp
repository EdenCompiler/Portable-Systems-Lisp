(defstruct/packed packed_packet
  (tag u8)
  (value u64)
  (delta s16)
  (address (ptr u8)))

(defstruct/packed packed_outer
  (prefix u8)
  (packet packed_packet)
  (tail u32))

(defcstruct natural_pair (tag u8) (value u32))
(defstruct/packed packed_bridge
  (head u8) (pair natural_pair) (tail u8))

(defun packed_packet_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'packed_packet))

(defun packed_packet_alignment ()
  (declare (returns usize) (c-export :c))
  (alignof 'packed_packet))

(defun packed_packet_address_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of 'packed_packet 'address))

(defun packed_outer_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'packed_outer))

(defun packed_bridge_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'packed_bridge))

(defun packed_bridge_tail ()
  (declare (returns usize) (c-export :c))
  (offset-of 'packed_bridge 'tail))

(defun packed_update (packet value delta address)
  (declare (type (ptr packed_packet) packet) (type u64 value)
           (type s16 delta) (type (ptr u8) address)
           (returns u64) (c-export :c))
  (store (field-pointer packet 'value) value)
  (store (field-pointer packet 'delta) delta)
  (store (field-pointer packet 'address) address)
  (wrap+ (deref (field-pointer packet 'value))
         (wrap-cast u64 (deref (field-pointer packet 'delta)))))

(defun packed_nested_read (outer)
  (declare (type (ptr packed_outer) outer) (returns u64) (c-export :c))
  (deref (field-pointer (field-pointer outer 'packet) 'value)))

(defun packed_read_address (packet)
  (declare (type (ptr packed_packet) packet) (returns (ptr u8)) (c-export :c))
  (deref (field-pointer packet 'address)))
