#include "internal.h"

static _Thread_local psl_value current_values[2];
static _Thread_local size_t current_count;
static _Thread_local int initialized;

static void ensure_values_roots(void) {
    if (!initialized) {
        psl_rt_register_permanent_roots(current_values, 2);
        initialized = 1;
    }
}

psl_value psl_rt_values2(psl_value first, psl_value second) {
    ensure_values_roots();
    current_values[0] = first;
    current_values[1] = second;
    current_count = 2;
    return first;
}

psl_value psl_rt_nth_value(size_t index) {
    ensure_values_roots();
    return index < current_count ? current_values[index] : PSL_NIL;
}

size_t psl_rt_value_count(void) {
    return current_count;
}
