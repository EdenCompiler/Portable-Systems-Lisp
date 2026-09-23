#include "internal.h"

#include <stdlib.h>

psl_value psl_rt_fixnum(int64_t number) {
    if (number < -(INT64_C(1) << 62) || number >= (INT64_C(1) << 62)) {
        abort();
    }
    return ((uint64_t)number << 1) | UINT64_C(1);
}

int64_t psl_rt_unbox_fixnum(psl_value value) {
    if (!psl_rt_fixnum_p(value)) {
        abort();
    }
    uint64_t payload = value >> 1;
    if (payload < (UINT64_C(1) << 62)) {
        return (int64_t)payload;
    }
    return -1 - (int64_t)((~payload) & ((UINT64_C(1) << 63) - 1));
}

int psl_rt_fixnum_p(psl_value value) {
    return (value & UINT64_C(1)) != 0;
}

int psl_rt_nil_p(psl_value value) {
    return value == PSL_NIL;
}

uint64_t psl_rt_truthy(psl_value value) {
    return value != PSL_NIL;
}

uint64_t psl_rt_eq(psl_value left, psl_value right) {
    return left == right;
}
