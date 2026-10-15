(include "../target.lisp")
(include "common.lisp")
(include "fixups.lisp")
(include "aarch64_encode.lisp")
(include "riscv64_encode.lisp")
;; Every caller validates the complete instruction extent before these reads.
(defun native_function_address_read_word (code offset)
  (declare (type (ptr byte_buffer) code) (type usize offset) (returns u64))
  (wrap-cast u64 (read_u32_le (pointer+ (deref (field-pointer code 'data))
                                      (wrap-cast isize offset)))))
(include "x86_function_addresses.lisp")
(include "a64_function_addresses.lisp")
(include "rv_function_addresses.lisp")

(defun native_function_address_size (target)
  (declare (type u32 target) (returns usize))
  (cond ((= (native_target_architecture target) 1) 7)
        ((= (native_target_architecture target) 2) 24)
        ((= (native_target_architecture target) 3) 8) (t 0)))

(defun native_function_address_buffer_p (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (ptr-address code) 0) 0
      (if (= (ptr-address (deref (field-pointer code 'data))) 0) 0
          (if (< (deref (field-pointer code 'capacity)) (deref (field-pointer code 'length))) 0 1))))

(defun native_function_address_arena_p (addresses)
  (declare (type (ptr native_fixup_arena) addresses) (returns c-int))
  (if (= (ptr-address addresses) 0) 0
      (if (< (deref (field-pointer addresses 'capacity)) (deref (field-pointer addresses 'count))) 0
          (if (< 0 (deref (field-pointer addresses 'error))) 0
              (if (= (ptr-address (deref (field-pointer addresses 'items))) 0) 0 1)))))

(defun native_encode_function_address (target code addresses function)
  (declare (type u32 target) (type (ptr byte_buffer) code)
           (type (ptr native_fixup_arena) addresses) (type usize function)
           (returns c-int) (c-export :c))
  (if (= (native_target_valid_p target) 0) 0
      (if (= function 0) 0
          (if (= (native_function_address_buffer_p code) 0) 0
                  (if (= (native_function_address_arena_p addresses) 0) 0
                  (if (= (deref (field-pointer addresses 'count)) (deref (field-pointer addresses 'capacity))) 0
                      (if (= (room_for code (native_function_address_size target)) 0) 0
                          (let ((anchor (deref (field-pointer code 'length))))
                            (if (= (cond
                                     ((= (native_target_architecture target) 1) (x86_encode_function_address code))
                                     ((= (native_target_architecture target) 2) (a64_encode_function_address code))
                                     (t (rv_encode_function_address code))) 0) 0
                                (record_call_fixup addresses anchor function))))))))))

(defun native_function_address_entry_p (target code functions count entry)
  (declare (type u32 target) (type (ptr byte_buffer) code)
           (type (ptr native_function) functions) (type usize count)
           (type (ptr native_call_fixup) entry) (returns c-int))
  (let ((reference (deref (field-pointer entry 'target)))
        (anchor (deref (field-pointer entry 'instruction)))
        (length (deref (field-pointer code 'length))))
    (if (if (= reference 0) t (< count reference)) 0
        (if (< length anchor) 0
            (if (< (wrap- length anchor) (native_function_address_size target)) 0
                (let ((function (native_function_at functions (wrap- reference 1))))
                  (let ((destination (deref (field-pointer function 'offset)))
                        (size (deref (field-pointer function 'size))))
                    (if (= (native_function_defined_target_p functions count reference) 1)
                        (if (if (= size 0) t (< length destination)) 0
                            (if (< (wrap- length destination) size) 0
                                (cond
                                  ((= (native_target_architecture target) 1)
                                   (if (= (x86_function_address_shape_p code anchor) 0) 0
                                       (x86_function_address_range_p destination anchor)))
                                  ((= (native_target_architecture target) 2) (a64_function_address_shape_p code anchor))
                                  (t (if (= (rv_function_address_shape_p code anchor) 0) 0
                                         (rv_function_address_range_p destination anchor)))))) 0))))))))

(defun native_function_addresses_valid_p (target code functions count addresses index)
  (declare (type u32 target) (type (ptr byte_buffer) code)
           (type (ptr native_function) functions) (type usize count index)
           (type (ptr native_fixup_arena) addresses) (returns c-int))
  (if (= index (deref (field-pointer addresses 'count))) 1
      (if (= (native_function_address_entry_p target code functions count (call_fixup_at addresses index)) 0) 0
          (native_function_addresses_valid_p target code functions count addresses (wrap+ index 1)))))

(defun native_patch_function_addresses_from (target code functions addresses index)
  (declare (type u32 target) (type (ptr byte_buffer) code)
           (type (ptr native_function) functions) (type usize index)
           (type (ptr native_fixup_arena) addresses) (returns c-int))
  (if (= index (deref (field-pointer addresses 'count))) 1
      (let ((entry (call_fixup_at addresses index)))
        (let ((anchor (deref (field-pointer entry 'instruction)))
              (destination (deref (field-pointer (native_function_at functions
                              (wrap- (deref (field-pointer entry 'target)) 1)) 'offset))))
          (if (= (cond
                   ((= (native_target_architecture target) 1) (x86_patch_function_address code anchor destination))
                   ((= (native_target_architecture target) 2) (a64_patch_function_address code anchor destination))
                   (t (rv_patch_function_address code anchor destination))) 0) 0
              (native_patch_function_addresses_from target code functions addresses (wrap+ index 1)))))))

(defun native_patch_function_addresses (target code functions count addresses)
  (declare (type u32 target) (type (ptr byte_buffer) code)
           (type (ptr native_function) functions) (type usize count)
           (type (ptr native_fixup_arena) addresses) (returns c-int) (c-export :c))
  (if (= (native_target_valid_p target) 0) 0
      (if (= (native_function_address_buffer_p code) 0) 0
          (if (= (native_function_address_arena_p addresses) 0) 0
              (if (= (deref (field-pointer addresses 'count)) 0) 1
                  (if (= (ptr-address functions) 0) 0
                      (if (= (native_function_addresses_valid_p target code functions count addresses 0) 0) 0
                          (native_patch_function_addresses_from target code functions addresses 0))))))))

;; Leaf C-ABI return used by interop gates; ordinary LIR encoding uses the
;; working-register entry above and its own verified function epilogue.
(defun native_encode_function_address_return (target code addresses function)
  (declare (type u32 target) (type (ptr byte_buffer) code)
           (type (ptr native_fixup_arena) addresses) (type usize function)
           (returns c-int) (c-export :c))
  (if (= (native_target_valid_p target) 0) 0
      (if (= (native_function_address_buffer_p code) 0) 0
          (if (= (room_for code (wrap+ (native_function_address_size target)
                      (if (= (native_target_architecture target) 1) (wrap-cast usize 1) (wrap-cast usize 8)))) 0) 0
              (if (= (native_encode_function_address target code addresses function) 0) 0
                  (cond
                    ((= (native_target_architecture target) 1) (emit_integer code #xc3 1))
                    ((= (native_target_architecture target) 2)
                     (if (= (a64_register_op code #xaa000000 0 31 9) 0) 0 (a64_word code #xd65f03c0)))
                    (t (if (= (rv_move code 10 5) 0) 0 (rv_word code #x00008067)))))))))
