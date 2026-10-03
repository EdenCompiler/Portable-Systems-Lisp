#ifndef PSL_NATIVE_MACROS_H
#define PSL_NATIVE_MACROS_H
#include "../environment.h"
struct psl_parser;
struct native_compile_context;
/* Build-host rewrites use caller-owned syntax and identity arenas. Inputs must
   already have resolved identities. Origins point to the same or an earlier
   node; generated trees are verified before language analysis. Errors latch.
   Failed expansion rolls arena counts back and leaves original nodes intact. */
enum native_macro_error {
    NATIVE_MACRO_CAPACITY=1, NATIVE_MACRO_ARITY=2, NATIVE_MACRO_REFERENCE=4,
    NATIVE_MACRO_DEPTH=5, NATIVE_MACRO_UNSUPPORTED=10
};
struct native_tree_context {
    struct psl_parser *parser;
    struct native_reader_environment *reader;
    uintptr_t origin, depth, limit, cursor;
    uint32_t error;
    uintptr_t remaining, last;
};
struct native_macro_definition { uintptr_t symbol, parameters, body; };
struct native_macro_registry {
    struct psl_parser *parser;
    const uint8_t *source;
    struct native_tree_context *tree;
    struct native_macro_definition *definitions;
    uintptr_t count, capacity;
    uint32_t error;
};
struct native_macro_binding { uintptr_t symbol, form; };
struct native_macro_expansion { uintptr_t form; int32_t expanded; };
struct native_macro_call {
    struct native_macro_registry *registry;
    struct native_macro_binding *bindings;
    uintptr_t count, capacity, origin;
    uint32_t error;
    uintptr_t steps, step_limit;
    struct native_macro_expansion expansion, repeated;
};
extern int native_tree_verify(struct native_tree_context *,uintptr_t);
extern uintptr_t native_tree_copy(struct native_tree_context *,uintptr_t);
extern uintptr_t native_macro_register(struct native_macro_registry *,uintptr_t);
extern uintptr_t native_macro_lookup(struct native_macro_registry *,uintptr_t);
extern int native_macro_prepare_call(struct native_macro_call *,uintptr_t,uintptr_t);
extern int native_macroexpand_1(struct native_macro_call *,uintptr_t,struct native_macro_expansion *);
extern int native_macroexpand(struct native_macro_call *,uintptr_t,struct native_macro_expansion *);
extern uintptr_t native_expand_function_macros(struct native_compile_context *,uintptr_t);
#endif
