#include "internal.h"

static psl_value make_symbol(psl_value name, int precise) {
    (void)psl_rt_expect_object(name, PSL_OBJECT_STRING);
    psl_root root;
    psl_rt_push_roots(&root, &name, 1);
    psl_object *symbol = precise ? psl_rt_allocate_precise(PSL_OBJECT_SYMBOL, 0)
                                 : psl_rt_allocate(PSL_OBJECT_SYMBOL, 0);
    symbol->slots[0] = name;
    symbol->slots[1] = PSL_NIL;
    symbol->slots[2] = PSL_NIL;
    psl_rt_pop_roots(&root);
    return (psl_value)(uintptr_t)symbol;
}

psl_value psl_rt_make_symbol(psl_value name) {
    return make_symbol(name, 0);
}

psl_value psl_rt_make_symbol_precise(psl_value name) {
    return make_symbol(name, 1);
}

psl_value psl_rt_symbol_name(psl_value symbol) {
    return psl_rt_expect_object(symbol, PSL_OBJECT_SYMBOL)->slots[0];
}
