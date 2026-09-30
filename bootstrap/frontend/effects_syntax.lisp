(defun allocation_region_word_p (parser source reference)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize reference) (returns c-int))
  (if (= reference 0) 0
      (let ((node (parser_node parser reference)))
        (if (= (deref (field-pointer node 'kind)) 8)
            (let ((offset (source_builtin_offset source
                    (deref (field-pointer node 'start))
                    (deref (field-pointer node 'length)) 18 2)))
              (if (= offset 0) 0
                  (let ((start (wrap+ (deref (field-pointer node 'start))
                                     (wrap- offset 1))))
                    (if (= (ascii_matches source start #x2d74756f68746977 8) 0) 0
                        (if (= (ascii_matches source (wrap+ start 8) #x697461636f6c6c61 8) 0) 0
                            (ascii_matches source (wrap+ start 16) #x6e6f 2))))))
            0))))

(defun analyze_allocation_region (context body depth)
  (declare (type (ptr native_compile_context) context) (type usize body depth)
           (returns usize))
  (let ((result (analyze_progn_expr context body depth)))
    (if (= result 0) 0
        (progn
          (store (field-pointer (hir_node_at (deref (field-pointer context 'hir)) result)
                                'allocation_region) body)
          result))))
