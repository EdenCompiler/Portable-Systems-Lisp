;; Native hosted closures lift a real lambda AST into a private callback and
;; keep its lexical VALUEs in an ordinary precise CONS environment.

(defun native_closure_plan_at (context index)
  (declare (type (ptr native_compile_context) context) (type usize index)
           (returns (ptr native_closure_plan)))
  (pointer+ (deref (field-pointer context 'closure_plans))
            (wrap-cast isize index)))
(defun native_closure_plan_index (context origin index)
  (declare (type (ptr native_compile_context) context)
           (type usize origin index) (returns usize))
  (if (= index (deref (field-pointer context 'closure_plan_count))) 0
      (if (= (deref (field-pointer (native_closure_plan_at context index) 'origin)) origin)
          (wrap+ index 1)
          (native_closure_plan_index context origin (wrap+ index 1)))))
(defun native_closure_capture_at (context index)
  (declare (type (ptr native_compile_context) context) (type usize index)
           (returns (ptr native_closure_capture)))
  (pointer+ (deref (field-pointer context 'closure_captures))
            (wrap-cast isize index)))
(defun native_closure_capture_duplicate_p (context name binding stop)
  (declare (type (ptr native_compile_context) context)
           (type usize name binding stop) (returns c-int))
  (if (= binding stop) 0
      (let ((node (hir_node_at (deref (field-pointer context 'hir)) binding)))
        (if (= (ast_same_name_p (deref (field-pointer context 'parser))
               (deref (field-pointer context 'source)) name
               (deref (field-pointer node 'source))) 1)
            1
            (native_closure_capture_duplicate_p
             context name (deref (field-pointer node 'target)) stop)))))
(defun native_ast_name_occurs_in_forms_p (context form wanted shadowed depth)
  (declare (type (ptr native_compile_context) context)
           (type usize form wanted depth) (type u8 shadowed)
           (returns c-int))
  (if (= form 0) 0
      (if (= (native_compile_depth_exceeded_p depth) 1) 0
          (let ((parser (deref (field-pointer context 'parser)))
                (source (deref (field-pointer context 'source))))
            (let ((node (parser_node parser form))
                  (kind (deref (field-pointer (parser_node parser form) 'kind))))
              (cond
                ((= kind 8)
                 (if (= shadowed 1) 0
                     (ast_same_name_p parser source form wanted)))
                ((= kind 9)
                 (native_ast_name_occurs_in_forms_p
                  context (ast_first parser form) wanted shadowed
                  (wrap+ depth 1)))
                ((= kind 1)
                 (native_ast_list_name_occurs_p context form wanted shadowed depth))
                (t 0)))))))
(defun native_ast_siblings_name_occurs_p (context item wanted shadowed depth)
  (declare (type (ptr native_compile_context) context)
           (type usize item wanted depth) (type u8 shadowed)
           (returns c-int))
  (if (= item 0) 0
      (if (= (native_ast_name_occurs_in_forms_p context item wanted shadowed
                                                (wrap+ depth 1)) 1)
          1
          (native_ast_siblings_name_occurs_p
           context (ast_next (deref (field-pointer context 'parser)) item)
           wanted shadowed (wrap+ depth 1)))))
(defun native_ast_list_name_occurs_p (context form wanted shadowed depth)
  (declare (type (ptr native_compile_context) context)
           (type usize form wanted depth) (type u8 shadowed)
           (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((head (ast_first parser form))
          (first-argument (ast_next parser (ast_first parser form))))
      (cond
        ((= (ast_package_name_p parser head 1 (ffi:c-string "LET") 3) 1)
         (native_ast_let_name_occurs_p
          context (ast_first parser first-argument)
          (ast_next parser first-argument) wanted shadowed (wrap+ depth 1)))
        ((= (ast_package_name_p parser head 1 (ffi:c-string "LAMBDA") 6) 1)
         (native_ast_lambda_name_occurs_p context form wanted shadowed
                                          (wrap+ depth 1)))
        ((= (ast_package_name_p parser head 1 (ffi:c-string "FUNCTION") 8) 1)
         (native_ast_siblings_name_occurs_p context first-argument wanted
                                            shadowed (wrap+ depth 1)))
        ((= (ast_package_name_p parser head 1 (ffi:c-string "QUOTE") 5) 1) 0)
        (t (native_ast_siblings_name_occurs_p
            context first-argument wanted shadowed (wrap+ depth 1)))))))
(defun native_ast_let_binding_name_p (context bindings wanted)
  (declare (type (ptr native_compile_context) context)
           (type usize bindings wanted) (returns c-int))
  (if (= bindings 0) 0
      (let ((parser (deref (field-pointer context 'parser)))
            (source (deref (field-pointer context 'source))))
        (let ((binding (ast_first parser bindings)))
          (if (= (ast_same_name_p parser source (ast_first parser binding) wanted) 1)
              1
              (native_ast_let_binding_name_p context (ast_next parser binding) wanted))))))
(defun native_ast_let_initializers_name_occurs_p (context bindings wanted shadowed depth)
  (declare (type (ptr native_compile_context) context)
           (type usize bindings wanted depth) (type u8 shadowed) (returns c-int))
  (if (= bindings 0) 0
      (let ((parser (deref (field-pointer context 'parser))))
        (let ((initializer (ast_next parser (ast_first parser bindings)))
              (next (ast_next parser bindings)))
          (if (= (native_ast_name_occurs_in_forms_p
                  context initializer wanted shadowed (wrap+ depth 1)) 1)
              1
              (native_ast_let_initializers_name_occurs_p
               context next wanted shadowed (wrap+ depth 1)))))))
(defun native_ast_let_name_occurs_p (context bindings body wanted shadowed depth)
  (declare (type (ptr native_compile_context) context)
           (type usize bindings body wanted depth) (type u8 shadowed) (returns c-int))
  (if (= (native_ast_let_initializers_name_occurs_p
          context bindings wanted shadowed (wrap+ depth 1)) 1)
      1
      (if (= shadowed 1)
          0
          (if (= (native_ast_let_binding_name_p context bindings wanted) 1)
              0
              (native_ast_siblings_name_occurs_p context body wanted shadowed
                                                 (wrap+ depth 1))))))
(defun native_ast_let_body_name_occurs_p (context bindings body wanted shadowed added depth)
  (declare (type (ptr native_compile_context) context)
           (type usize bindings body wanted depth) (type u8 shadowed added)
           (returns c-int))
  (if (= body 0) 0
      (let ((parser (deref (field-pointer context 'parser))))
        (if (= (native_ast_name_occurs_in_forms_p
                context body wanted
                (if (= added 1) 1 shadowed) (wrap+ depth 1)) 1)
            1
            (native_ast_siblings_name_occurs_p
             context (ast_next parser body) wanted
             (if (= added 1) 1 shadowed) (wrap+ depth 1))))))
(defun native_ast_lambda_name_occurs_p (context lambda wanted shadowed depth)
  (declare (type (ptr native_compile_context) context)
           (type usize lambda wanted depth) (type u8 shadowed)
           (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (let ((parameters (ast_next parser (ast_first parser lambda))))
      (let ((argument (ast_first parser parameters))
            (body (ast_next parser parameters)))
        (native_ast_siblings_name_occurs_p
         context body wanted
         (if (= (ast_same_name_p parser source argument wanted) 1) 1 shadowed)
         (wrap+ depth 1))))))
(defun native_lambda_needs_capture_p (context lambda wanted)
  (declare (type (ptr native_compile_context) context)
           (type usize lambda wanted) (returns c-int))
  (native_ast_lambda_name_occurs_p context lambda wanted 0 0))
(defun native_closure_record_capture (context plan name)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_closure_plan) plan) (type usize name)
           (returns c-int))
  (let ((count (deref (field-pointer context 'closure_capture_count)))
        (capacity (deref (field-pointer context 'closure_capture_capacity))))
    (if (= count capacity) 0
        (progn
          (store (field-pointer (native_closure_capture_at context count) 'name) name)
          (store (field-pointer plan 'capture_count)
                 (wrap+ (deref (field-pointer plan 'capture_count)) 1))
          (store (field-pointer context 'closure_capture_count) (wrap+ count 1))
          1))))
(defun native_closure_prepare_captures_from (context plan lambda binding stop)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_closure_plan) plan)
           (type usize lambda binding stop) (returns c-int))
  (if (= binding stop) 1
      (let ((node (hir_node_at (deref (field-pointer context 'hir)) binding)))
        (let ((name (deref (field-pointer node 'source))))
          (if (= (native_closure_capture_duplicate_p context name
                  (deref (field-pointer context 'active_binding)) binding) 1)
              (native_closure_prepare_captures_from
               context plan lambda (deref (field-pointer node 'target)) stop)
              (if (= (native_lambda_needs_capture_p context lambda name) 0)
                  (native_closure_prepare_captures_from
                   context plan lambda (deref (field-pointer node 'target)) stop)
                  (if (= (hir_scalar_code (deref (field-pointer context 'hir)) binding) 15)
                      (if (= (native_closure_record_capture context plan name) 0) 0
                          (native_closure_prepare_captures_from
                           context plan lambda (deref (field-pointer node 'target)) stop))
                      0)))))))
(defun native_closure_prepare_parameters_from (context plan lambda index stop)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_closure_plan) plan)
           (type usize lambda index stop) (returns c-int))
  (if (= index stop) 1
      (let ((signature (deref (field-pointer context 'current_signature)))
            (signatures (deref (field-pointer context 'signatures))))
        (let ((parameter (native_parameter_at
                          signatures
                          (wrap+ (deref (field-pointer signature 'first_parameter)) index))))
          (let ((name (deref (field-pointer parameter 'name))))
            (if (= name 0)
                (native_closure_prepare_parameters_from context plan lambda
                                                       (wrap+ index 1) stop)
                (if (= (native_closure_capture_duplicate_p
                        context name (deref (field-pointer context 'active_binding)) 0) 1)
                    (native_closure_prepare_parameters_from context plan lambda
                                                           (wrap+ index 1) stop)
                    (if (= (native_lambda_needs_capture_p context lambda name) 0)
                        (native_closure_prepare_parameters_from context plan lambda
                                                               (wrap+ index 1) stop)
                        (if (= (scalar_signature_parameter_code context signature index) 15)
                            (if (= (native_closure_record_capture context plan name) 0) 0
                                (native_closure_prepare_parameters_from context plan lambda
                                                                       (wrap+ index 1) stop))
                            0)))))))))
(defun native_hir_runtime_pair_call (context id source left right)
  (declare (type (ptr native_compile_context) context)
           (type u32 id) (type usize source left right) (returns usize))
  (let ((arena (deref (field-pointer context 'hir)))
        (index (native_runtime_function_index context id 0)))
    (if (= index 0) 0
        (let ((first (hir_new_scalar arena 17 0 left 0 0 source
                                     (hir_scalar_code arena left))))
          (if (= first 0) 0
              (let ((chain (hir_new_scalar arena 17 0 right first 0 source
                                            (hir_scalar_code arena right))))
                (if (= chain 0) 0
                    (hir_new_scalar arena 7 0 chain 0 index source 15))))))))
(defun native_hir_runtime_single_call (context id source argument)
  (declare (type (ptr native_compile_context) context)
           (type u32 id) (type usize source argument) (returns usize))
  (let ((arena (deref (field-pointer context 'hir)))
        (index (native_runtime_function_index context id 0)))
    (if (= index 0) 0
        (let ((chain (hir_new_scalar arena 17 0 argument 0 0 source
                                     (hir_scalar_code arena argument))))
          (if (= chain 0) 0
              (hir_new_scalar arena 7 0 chain 0 index source 15))))))
(defun native_closure_env_list_from (context plan index source)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_closure_plan) plan) (type usize index source)
           (returns usize))
  (if (= index (deref (field-pointer plan 'capture_count)))
      (hir_new_scalar (deref (field-pointer context 'hir)) 1 2 0 0 0 source 15)
      (let ((rest (native_closure_env_list_from context plan (wrap+ index 1) source)))
        (if (= rest 0) 0
            (let ((capture (native_closure_capture_at
                            context (wrap+ (deref (field-pointer plan 'capture_first)) index))))
              (let ((name (deref (field-pointer capture 'name))))
                (let ((value (hir_from_variable context name)))
                  (if (= value 0) 0
                      (native_hir_runtime_pair_call context 1 source value rest)))))))))
(defun native_closure_function_value (context plan origin)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_closure_plan) plan) (type usize origin)
           (returns usize))
  (let ((address (hir_new_scalar (deref (field-pointer context 'hir))
                   36 0 0 0 (wrap+ (deref (field-pointer plan 'function_index)) 1)
                   origin 2)))
    (if (= address 0) 0
        (let ((environment (native_closure_env_list_from context plan 0 origin)))
          (if (= environment 0) 0
              (native_hir_runtime_pair_call context 22 origin address environment))))))
(defun native_closure_expression (context lambda source depth)
  (declare (type (ptr native_compile_context) context)
           (type usize lambda source depth) (returns usize))
  (let ((plan-index (native_closure_plan_index context lambda 0)))
    (if (= plan-index 0) 0
        (let ((plan (native_closure_plan_at context (wrap- plan-index 1))))
          (if (= (deref (field-pointer plan 'captures_ready)) 0)
              (progn
                (store (field-pointer plan 'capture_first)
                       (deref (field-pointer context 'closure_capture_count)))
                (store (field-pointer plan 'capture_count) 0)
                (if (= (native_closure_prepare_parameters_from
                        context plan lambda 0
                        (deref (field-pointer context 'current_arity))) 0)
                    0
                    (if (= (native_closure_prepare_captures_from
                            context plan lambda
                            (deref (field-pointer context 'active_binding)) 0) 0)
                        0
                        (progn
                          (store (field-pointer plan 'captures_ready) 1)
                          (native_closure_function_value context plan lambda)))))
              (native_closure_function_value context plan lambda))))))
(defun native_lambda_expression_origin (context form)
  (declare (type (ptr native_compile_context) context) (type usize form)
           (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((node (parser_node parser form)))
      (cond
        ((= (native_lambda_origin_p context form) 1) form)
        ((= (deref (field-pointer node 'kind)) 9)
         (let ((operand (ast_first parser form)))
           (if (= (ast_next parser operand) 0)
               (if (= (native_lambda_origin_p context operand) 1) operand 0)
               0)))
        ((= (ast_list_p parser form) 1)
         (let ((head (ast_first parser form))
               (operand (ast_next parser (ast_first parser form))))
           (if (= (ast_package_name_p parser head 1 (ffi:c-string "FUNCTION") 8) 1)
               (if (= (ast_next parser operand) 0)
                   (if (= (native_lambda_origin_p context operand) 1) operand 0)
                   0)
               0)))
        (t 0)))))
(defun analyze_native_lambda_form (context form depth)
  (declare (type (ptr native_compile_context) context)
           (type usize form depth) (returns usize))
  (if (= (deref (field-pointer context 'profile)) 1)
      (let ((origin (native_lambda_expression_origin context form)))
        (if (= origin 0) 0
            (native_closure_expression context origin form depth)))
      0))
(defun native_generated_capture_bindings_from (context plan tail index previous)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_closure_plan) plan)
           (type usize tail index previous) (returns usize))
  (if (= index (deref (field-pointer plan 'capture_count))) previous
      (let ((arena (deref (field-pointer context 'hir)))
            (source (deref (field-pointer plan 'origin))))
        (let ((value (native_hir_runtime_single_call context 2 source tail)))
          (if (= value 0) 0
              (let ((capture (native_closure_capture_at
                              context (wrap+ (deref (field-pointer plan 'capture_first)) index))))
                (let ((name (deref (field-pointer capture 'name)))
                      (slot (wrap+ (deref (field-pointer context 'local_count)) 1)))
                  (store (field-pointer context 'local_count) slot)
                  (let ((binding (hir_copy_type arena
                                   (hir_new_scalar arena 14 (wrap-cast u64 slot)
                                                   value 0 previous name 15) value)))
                    (if (= binding 0) 0
                        (progn
                          (store (field-pointer context 'active_binding) binding)
                          (let ((rest (native_hir_runtime_single_call context 3 source tail)))
                            (if (= rest 0) 0
                                (native_generated_capture_bindings_from
                                 context plan rest (wrap+ index 1) binding)))))))))))))
(defun native_analyze_closure_body_with_bindings (context plan bindings)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_closure_plan) plan) (type usize bindings)
           (returns usize))
  (store (field-pointer context 'active_binding) bindings)
  (let ((body (analyze_scalar_sequence_from
               context (deref (field-pointer plan 'body)) 0
               (deref (field-pointer plan 'origin)) 0)))
    (if (= body 0) 0
        (if (= bindings 0) body
            (wrap_let_bindings context bindings 0 body
                               (deref (field-pointer plan 'origin)))))))

(defun analyze_generated_closure_body (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature) (returns usize))
  (let ((plan-index (deref (field-pointer signature 'generated_plan))))
    (let ((plan (native_closure_plan_at context (wrap- plan-index 1))))
      (let ((environment (hir_new_scalar (deref (field-pointer context 'hir)) 2 1
                                         0 0 0 (deref (field-pointer plan 'origin)) 15)))
        (if (= environment 0) 0
            (let ((bindings (native_generated_capture_bindings_from
                             context plan environment 0 0)))
              (if (= bindings 0)
                  (if (= (deref (field-pointer plan 'capture_count)) 0)
                      (native_analyze_closure_body_with_bindings context plan 0)
                      0)
                  (native_analyze_closure_body_with_bindings context plan bindings))))))))

(defun native_closure_name_digit (digit)
  (declare (type u32 digit) (returns u8))
  (cond
    ((= digit 0) 48) ((= digit 1) 49) ((= digit 2) 50) ((= digit 3) 51)
    ((= digit 4) 52) ((= digit 5) 53) ((= digit 6) 54) ((= digit 7) 55)
    ((= digit 8) 56) ((= digit 9) 57) ((= digit 10) 97) ((= digit 11) 98)
    ((= digit 12) 99) ((= digit 13) 100) ((= digit 14) 101) (t 102)))
(defun native_closure_write_name (context plan-index)
  (declare (type (ptr native_compile_context) context)
           (type usize plan-index) (returns c-int))
  (if (< #xffffffff plan-index) 0
      (let ((base (pointer+ (deref (field-pointer context 'closure_names))
                            (wrap-cast isize (wrap* plan-index 16)))))
        (store (pointer+ base 0) 112)
        (store (pointer+ base 1) 115)
        (store (pointer+ base 2) 108)
        (store (pointer+ base 3) 95)
        (store (pointer+ base 4) 108)
        (store (pointer+ base 5) 95)
        (store (pointer+ base 6) (native_closure_name_digit (bits-and (wrap-cast u32 (shr64 (wrap-cast u64 plan-index) 28)) 15)))
        (store (pointer+ base 7) (native_closure_name_digit (bits-and (wrap-cast u32 (shr64 (wrap-cast u64 plan-index) 24)) 15)))
        (store (pointer+ base 8) (native_closure_name_digit (bits-and (wrap-cast u32 (shr64 (wrap-cast u64 plan-index) 20)) 15)))
        (store (pointer+ base 9) (native_closure_name_digit (bits-and (wrap-cast u32 (shr64 (wrap-cast u64 plan-index) 16)) 15)))
        (store (pointer+ base 10) (native_closure_name_digit (bits-and (wrap-cast u32 (shr64 (wrap-cast u64 plan-index) 12)) 15)))
        (store (pointer+ base 11) (native_closure_name_digit (bits-and (wrap-cast u32 (shr64 (wrap-cast u64 plan-index) 8)) 15)))
        (store (pointer+ base 12) (native_closure_name_digit (bits-and (wrap-cast u32 (shr64 (wrap-cast u64 plan-index) 4)) 15)))
        (store (pointer+ base 13) (native_closure_name_digit (bits-and (wrap-cast u32 plan-index) 15)))
        1)))
(defun native_closure_register_signature (context origin argument body)
  (declare (type (ptr native_compile_context) context)
           (type usize origin argument body) (returns c-int))
  (let ((plans (deref (field-pointer context 'closure_plans)))
        (plan-count (deref (field-pointer context 'closure_plan_count)))
        (plan-capacity (deref (field-pointer context 'closure_plan_capacity)))
        (signatures (deref (field-pointer context 'signatures)))
        (functions (deref (field-pointer context 'functions))))
    (let ((signature-count (deref (field-pointer signatures 'signature_count)))
          (signature-capacity (deref (field-pointer signatures 'signature_capacity)))
          (parameter-count (deref (field-pointer signatures 'parameter_count)))
          (parameter-capacity (deref (field-pointer signatures 'parameter_capacity))))
      (if (= plan-count plan-capacity)
          0
          (if (= signature-count signature-capacity)
              0
              (if (< (wrap- parameter-capacity parameter-count) 2)
                  0
                  (if (< (deref (field-pointer context 'closure_name_capacity))
                         (wrap* (wrap+ plan-count 1) 16))
                      0
                      (if (= (native_closure_write_name context plan-count) 0)
                          0
          (let ((plan (native_closure_plan_at context plan-count))
                (signature (native_signature_at signatures signature-count))
                (function (native_function_at functions signature-count))
                (first-name (pointer+ (deref (field-pointer context 'closure_names))
                                      (wrap-cast isize (wrap* plan-count 16)))))
            (store (field-pointer plan 'origin) origin)
            (store (field-pointer plan 'argument) argument)
            (store (field-pointer plan 'body) body)
            (store (field-pointer plan 'function_index) signature-count)
            (store (field-pointer plan 'capture_first) 0)
            (store (field-pointer plan 'capture_count) 0)
            (store (field-pointer plan 'captures_ready) 0)
            (store (field-pointer signature 'name) 0)
            (store (field-pointer signature 'first_parameter) parameter-count)
            (store (field-pointer signature 'arity) 2)
            (store (field-pointer signature 'result_type) 0)
            (store (field-pointer signature 'result_size) 8)
            (store (field-pointer signature 'result_kind) 5)
            (store (field-pointer signature 'body) body)
            (store (field-pointer signature 'exported) 0)
            (store (field-pointer signature 'imported) 0)
            (store (field-pointer signature 'allocation_free) 0)
            (store (field-pointer signature 'effect_ready) 0)
            (store (field-pointer signature 'runtime_id) 0)
            (store (field-pointer signature 'result_code) 15)
            (store (field-pointer signature 'runtime_name) (ptr-from-address (ptr u8) 0))
            (store (field-pointer signature 'runtime_name_length) 0)
            (store (field-pointer signature 'generated) 1)
            (store (field-pointer signature 'generated_origin) origin)
            (store (field-pointer signature 'generated_argument) argument)
            (store (field-pointer signature 'generated_body) body)
            (store (field-pointer signature 'generated_plan) (wrap+ plan-count 1))
            (let ((first (native_parameter_at signatures parameter-count))
                  (second (native_parameter_at signatures (wrap+ parameter-count 1))))
              (store (field-pointer first 'name) 0)
              (store (field-pointer first 'type_ast) 0)
              (store (field-pointer first 'size) 8)
              (store (field-pointer first 'kind) 5)
              (store (field-pointer first 'scalar_code) 15)
              (store (field-pointer second 'name) argument)
              (store (field-pointer second 'type_ast) 0)
              (store (field-pointer second 'size) 8)
              (store (field-pointer second 'kind) 5)
              (store (field-pointer second 'scalar_code) 15))
            (store (field-pointer function 'name) first-name)
            (store (field-pointer function 'name_length) 14)
            (store (field-pointer function 'referenced) 0)
            (store (field-pointer function 'offset) 0)
            (store (field-pointer function 'size) 0)
            (store (field-pointer function 'frame_size) 0)
            (store (field-pointer function 'prologue_size) 0)
            (store (field-pointer function 'imported) 0)
            (store (field-pointer function 'exported) 0)
            (store (field-pointer function 'arity) 2)
            (store (field-pointer signatures 'parameter_count) (wrap+ parameter-count 2))
            (store (field-pointer signatures 'signature_count) (wrap+ signature-count 1))
            (store (field-pointer context 'closure_plan_count) (wrap+ plan-count 1))
            1)))))))))
(defun native_collect_closure_tree (context node)
  (declare (type (ptr native_compile_context) context)
           (type usize node) (returns c-int))
  (if (= node 0) 1
      (let ((parser (deref (field-pointer context 'parser)))
            (kind (deref (field-pointer (parser_node
                                         (deref (field-pointer context 'parser)) node)
                                        'kind))))
        (let ((origin (native_lambda_expression_origin context node)))
          (if (= origin 0)
              (if (= (native_closure_quote_form_p context node) 1) 1
                  (native_collect_closure_children context
                                                   (if (= kind 1)
                                                       (ast_first parser node)
                                                       (if (= kind 9)
                                                           (ast_first parser node) 0))))
              (let ((plan-index (native_closure_plan_index context origin 0)))
                (if (= plan-index 0)
                    (let ((parameters (ast_next parser (ast_first parser origin))))
                      (if (= (native_closure_register_signature
                              context origin (ast_first parser parameters)
                              (ast_next parser parameters)) 0)
                          0
                          (native_collect_closure_children context (ast_first parser node))))
                          (native_collect_closure_children context (ast_first parser node)))))))))
(defun native_closure_quote_form_p (context node)
  (declare (type (ptr native_compile_context) context) (type usize node)
           (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (ast_list_p parser node) 0) 0
        (ast_package_name_p parser (ast_first parser node) 1
                            (ffi:c-string "QUOTE") 5))))
(defun native_collect_closure_children (context child)
  (declare (type (ptr native_compile_context) context)
           (type usize child) (returns c-int))
  (if (= child 0) 1
      (let ((parser (deref (field-pointer context 'parser))))
        (if (= (native_collect_closure_tree context child) 0) 0
            (native_collect_closure_children context (ast_next parser child))))))
(defun native_collect_function_closures (context index stop)
  (declare (type (ptr native_compile_context) context)
           (type usize index stop) (returns c-int))
  (if (= index stop) 1
      (let ((signature (native_signature_at (deref (field-pointer context 'signatures)) index)))
        (if (= (native_collect_closure_children context
                  (deref (field-pointer signature 'body))) 0)
            0
            (native_collect_function_closures context (wrap+ index 1) stop)))))
(defun native_closure_swap_bytes_from (left right index size)
  (declare (type (ptr u8) left right) (type usize index size)
           (returns c-int))
  (if (= index size) 1
      (let ((left-byte (deref (pointer+ left (wrap-cast isize index))))
            (right-byte (deref (pointer+ right (wrap-cast isize index)))))
        (store (pointer+ left (wrap-cast isize index)) right-byte)
        (store (pointer+ right (wrap-cast isize index)) left-byte)
        (native_closure_swap_bytes_from left right (wrap+ index 1) size))))
(defun native_closure_swap_bytes (left right size)
  (declare (type (ptr u8) left right) (type usize size)
           (returns c-int))
  (native_closure_swap_bytes_from left right 0 size))

(defun native_closure_swap_signature_fields (left right)
  (declare (type (ptr native_signature) left right) (returns c-int))
  (progn
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'name))
     (ptr-cast (ptr u8) (field-pointer right 'name)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'first_parameter))
     (ptr-cast (ptr u8) (field-pointer right 'first_parameter)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'arity))
     (ptr-cast (ptr u8) (field-pointer right 'arity)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'result_type))
     (ptr-cast (ptr u8) (field-pointer right 'result_type)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'result_size))
     (ptr-cast (ptr u8) (field-pointer right 'result_size)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'result_kind))
     (ptr-cast (ptr u8) (field-pointer right 'result_kind)) 4)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'body))
     (ptr-cast (ptr u8) (field-pointer right 'body)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'exported))
     (ptr-cast (ptr u8) (field-pointer right 'exported)) 1)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'imported))
     (ptr-cast (ptr u8) (field-pointer right 'imported)) 1)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'allocation_free))
     (ptr-cast (ptr u8) (field-pointer right 'allocation_free)) 1)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'effect_ready))
     (ptr-cast (ptr u8) (field-pointer right 'effect_ready)) 1)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'inline_base))
     (ptr-cast (ptr u8) (field-pointer right 'inline_base)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'inline_count))
     (ptr-cast (ptr u8) (field-pointer right 'inline_count)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'inline_result))
     (ptr-cast (ptr u8) (field-pointer right 'inline_result)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'runtime_id))
     (ptr-cast (ptr u8) (field-pointer right 'runtime_id)) 4)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'result_code))
     (ptr-cast (ptr u8) (field-pointer right 'result_code)) 4)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'runtime_name))
     (ptr-cast (ptr u8) (field-pointer right 'runtime_name)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'runtime_name_length))
     (ptr-cast (ptr u8) (field-pointer right 'runtime_name_length)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'generated))
     (ptr-cast (ptr u8) (field-pointer right 'generated)) 1)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'generated_origin))
     (ptr-cast (ptr u8) (field-pointer right 'generated_origin)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'generated_argument))
     (ptr-cast (ptr u8) (field-pointer right 'generated_argument)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'generated_body))
     (ptr-cast (ptr u8) (field-pointer right 'generated_body)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'generated_plan))
     (ptr-cast (ptr u8) (field-pointer right 'generated_plan)) 8)
    1))
(defun native_closure_swap_function_fields (left right)
  (declare (type (ptr native_function) left right) (returns c-int))
  (progn
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'name))
     (ptr-cast (ptr u8) (field-pointer right 'name)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'name_length))
     (ptr-cast (ptr u8) (field-pointer right 'name_length)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'offset))
     (ptr-cast (ptr u8) (field-pointer right 'offset)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'size))
     (ptr-cast (ptr u8) (field-pointer right 'size)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'arity))
     (ptr-cast (ptr u8) (field-pointer right 'arity)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'exported))
     (ptr-cast (ptr u8) (field-pointer right 'exported)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'imported))
     (ptr-cast (ptr u8) (field-pointer right 'imported)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'referenced))
     (ptr-cast (ptr u8) (field-pointer right 'referenced)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'frame_size))
     (ptr-cast (ptr u8) (field-pointer right 'frame_size)) 8)
    (native_closure_swap_bytes
     (ptr-cast (ptr u8) (field-pointer left 'prologue_size))
     (ptr-cast (ptr u8) (field-pointer right 'prologue_size)) 8)
    1))
(defun native_closure_swap_signatures (context left-index right-index)
  (declare (type (ptr native_compile_context) context)
           (type usize left-index right-index) (returns c-int))
  (let ((left (native_signature_at
               (deref (field-pointer context 'signatures)) left-index))
        (right (native_signature_at
                (deref (field-pointer context 'signatures)) right-index)))
    (if (= (native_closure_swap_signature_fields left right) 0) 0
        (let ((left-function (native_function_at
                              (deref (field-pointer context 'functions)) left-index))
              (right-function (native_function_at
                               (deref (field-pointer context 'functions)) right-index)))
          (native_closure_swap_function_fields left-function right-function)))))

(defun native_closure_move_signature_left (context index boundary)
  (declare (type (ptr native_compile_context) context)
           (type usize index boundary) (returns c-int))
  (if (= index boundary) 1
      (let ((signatures (deref (field-pointer context 'signatures))))
        (if (= (native_closure_swap_signatures context index (wrap- index 1)) 0)
            0
            (native_closure_move_signature_left context (wrap- index 1) boundary)))))

(defun native_closure_partition_signatures (context index boundary count)
  (declare (type (ptr native_compile_context) context)
           (type usize index boundary count) (returns c-int))
  (if (= index count) 1
      (let ((signatures (deref (field-pointer context 'signatures)))
            (signature (native_signature_at (deref (field-pointer context 'signatures)) index)))
        (if (= (deref (field-pointer signature 'imported)) 1)
            (native_closure_partition_signatures context (wrap+ index 1) boundary count)
            (if (= (native_closure_move_signature_left context index boundary) 0) 0
                (native_closure_partition_signatures context (wrap+ index 1)
                                                     (wrap+ boundary 1) count))))))

(defun native_closure_refresh_function_indices (context index count)
  (declare (type (ptr native_compile_context) context)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((signature (native_signature_at
                        (deref (field-pointer context 'signatures)) index)))
        (if (= (deref (field-pointer signature 'generated)) 1)
            (let ((plan-index (deref (field-pointer signature 'generated_plan))))
              (store (field-pointer (native_closure_plan_at context (wrap- plan-index 1))
                                    'function_index) index))
            (wrap-cast usize 1))
        (native_closure_refresh_function_indices context (wrap+ index 1) count))))

(defun native_collect_unit_closures (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (if (= (deref (field-pointer context 'profile)) 0) 1
      (let ((initial-count
             (deref (field-pointer (deref (field-pointer context 'signatures))
                                   'signature_count))))
        (if (= (native_collect_function_closures context 0 initial-count) 0) 0
            (let ((total (deref (field-pointer
                                (deref (field-pointer context 'signatures))
                                'signature_count))))
              (if (= (native_closure_partition_signatures context 0 0 total) 0) 0
                  (native_closure_refresh_function_indices context 0 total)))))))
