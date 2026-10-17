#ifndef PSL_HARNESS_BOOTSTRAP_MACRO_REGISTRY_H
#define PSL_HARNESS_BOOTSTRAP_MACRO_REGISTRY_H
#include "../runtime/psl_runtime.h"

static uintptr_t macro_test_open_definition_handle(size_t capacity) {
    uintptr_t handle = psl_rt_value_handle_open();
    psl_value vector = psl_rt_make_value_vector_precise(capacity, PSL_NIL);
    psl_rt_value_handle_set(handle, vector);
    return handle;
}

static void macro_test_close_definition_handle(uintptr_t handle) {
    psl_rt_value_handle_close(handle);
}
#endif
