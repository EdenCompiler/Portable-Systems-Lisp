#include "internal.h"

static psl_value make_cons(psl_value first, psl_value rest, int precise) {
    psl_value values[2] = {first, rest};
    psl_root roots;
    psl_rt_push_roots(&roots, values, 2);
    psl_object *pair = precise ? psl_rt_allocate_precise(PSL_OBJECT_CONS, 0)
                               : psl_rt_allocate(PSL_OBJECT_CONS, 0);
    pair->slots[0] = first;
    pair->slots[1] = rest;
    psl_rt_pop_roots(&roots);
    return (psl_value)(uintptr_t)pair;
}

psl_value psl_rt_cons(psl_value first, psl_value rest) {
    return make_cons(first, rest, 0);
}

psl_value psl_rt_cons_precise(psl_value first, psl_value rest) {
    return make_cons(first, rest, 1);
}

psl_value psl_rt_car(psl_value pair) {
    if (pair == PSL_NIL) {
        return PSL_NIL;
    }
    return psl_rt_expect_object(pair, PSL_OBJECT_CONS)->slots[0];
}

psl_value psl_rt_cdr(psl_value pair) {
    if (pair == PSL_NIL) {
        return PSL_NIL;
    }
    return psl_rt_expect_object(pair, PSL_OBJECT_CONS)->slots[1];
}
