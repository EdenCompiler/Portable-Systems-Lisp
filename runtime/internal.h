#ifndef PSL_RUNTIME_INTERNAL_H
#define PSL_RUNTIME_INTERNAL_H

#include "psl_runtime.h"

typedef struct psl_object {
    struct psl_object *next;
    psl_object_kind kind;
    uint8_t marked;
    size_t length;
    psl_value slots[3];
    psl_closure_code code;
    unsigned char bytes[];
} psl_object;

psl_object *psl_rt_allocate(psl_object_kind kind, size_t extra_bytes);
psl_object *psl_rt_expect_object(psl_value value, psl_object_kind kind);
void psl_rt_register_permanent_roots(psl_value *values, size_t count);
void *psl_rt_stack_top(void);
void *psl_rt_platform_stack_top(void);
int psl_rt_strings_equal(psl_value left, psl_value right);

#endif
