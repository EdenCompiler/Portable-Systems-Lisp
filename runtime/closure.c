#include "internal.h"

#include <stdlib.h>

psl_value psl_rt_make_closure(psl_closure_code code, psl_value environment) {
    if (code == NULL) {
        abort();
    }
    psl_root root;
    psl_rt_push_roots(&root, &environment, 1);
    psl_object *closure = psl_rt_allocate(PSL_OBJECT_CLOSURE, 0);
    closure->slots[0] = environment;
    closure->code = code;
    psl_rt_pop_roots(&root);
    return (psl_value)(uintptr_t)closure;
}

psl_value psl_rt_call_closure(psl_value closure_value, psl_value argument) {
    psl_value values[2] = {closure_value, argument};
    psl_root root;
    psl_rt_push_roots(&root, values, 2);
    psl_object *closure = psl_rt_expect_object(closure_value,
                                                PSL_OBJECT_CLOSURE);
    psl_value result = closure->code(closure->slots[0], argument);
    psl_rt_pop_roots(&root);
    return result;
}
