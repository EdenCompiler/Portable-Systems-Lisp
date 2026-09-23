#include "internal.h"

psl_value psl_rt_make_package(psl_value name) {
    (void)psl_rt_expect_object(name, PSL_OBJECT_STRING);
    psl_root root;
    psl_rt_push_roots(&root, &name, 1);
    psl_object *package = psl_rt_allocate(PSL_OBJECT_PACKAGE, 0);
    package->slots[0] = name;
    package->slots[1] = PSL_NIL;
    psl_rt_pop_roots(&root);
    return (psl_value)(uintptr_t)package;
}

psl_value psl_rt_package_name(psl_value package) {
    return psl_rt_expect_object(package, PSL_OBJECT_PACKAGE)->slots[0];
}

psl_value psl_rt_intern(psl_value package_value, psl_value name) {
    psl_object *package = psl_rt_expect_object(package_value,
                                                PSL_OBJECT_PACKAGE);
    (void)psl_rt_expect_object(name, PSL_OBJECT_STRING);
    for (psl_value current = package->slots[1]; current != PSL_NIL;) {
        psl_object *symbol = psl_rt_expect_object(current, PSL_OBJECT_SYMBOL);
        if (psl_rt_strings_equal(symbol->slots[0], name)) {
            return current;
        }
        current = symbol->slots[2];
    }
    psl_value roots[2] = {package_value, name};
    psl_root root;
    psl_rt_push_roots(&root, roots, 2);
    psl_value symbol_value = psl_rt_make_symbol(name);
    package = psl_rt_expect_object(package_value, PSL_OBJECT_PACKAGE);
    psl_object *symbol = psl_rt_expect_object(symbol_value, PSL_OBJECT_SYMBOL);
    symbol->slots[1] = package_value;
    symbol->slots[2] = package->slots[1];
    package->slots[1] = symbol_value;
    psl_rt_pop_roots(&root);
    return symbol_value;
}
