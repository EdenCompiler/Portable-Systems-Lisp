#ifndef PSL_RUNTIME_H
#define PSL_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

/* Version 1 hosted ABI: fixnums have bit 0 set; heap addresses have three
 * low zero bits. NIL and T are immediate values distinct from both. */
typedef uint64_t psl_value;

#define PSL_RUNTIME_ABI_VERSION 1

#define PSL_NIL UINT64_C(2)
#define PSL_TRUE UINT64_C(6)

typedef enum {
    PSL_OBJECT_CONS = 1,
    PSL_OBJECT_STRING,
    PSL_OBJECT_SYMBOL,
    PSL_OBJECT_PACKAGE,
    PSL_OBJECT_CLOSURE
} psl_object_kind;

typedef psl_value (*psl_closure_code)(psl_value environment, psl_value argument);

typedef struct psl_root {
    struct psl_root *previous;
    psl_value *values;
    size_t count;
} psl_root;

psl_value psl_rt_fixnum(int64_t number);
int64_t psl_rt_unbox_fixnum(psl_value value);
int psl_rt_fixnum_p(psl_value value);
int psl_rt_nil_p(psl_value value);
uint64_t psl_rt_truthy(psl_value value);
uint64_t psl_rt_eq(psl_value left, psl_value right);
psl_object_kind psl_rt_kind(psl_value value);

void psl_rt_push_roots(psl_root *root, psl_value *values, size_t count);
void psl_rt_pop_roots(psl_root *root);
void psl_rt_collect(void);
size_t psl_rt_live_objects(void);

psl_value psl_rt_cons(psl_value first, psl_value rest);
psl_value psl_rt_car(psl_value pair);
psl_value psl_rt_cdr(psl_value pair);

psl_value psl_rt_make_string(size_t length, uint8_t fill);
size_t psl_rt_string_length(psl_value string);
uint8_t psl_rt_string_byte(psl_value string, size_t index);
void psl_rt_string_set_byte(psl_value string, size_t index, uint8_t byte);

psl_value psl_rt_make_symbol(psl_value name);
psl_value psl_rt_symbol_name(psl_value symbol);
psl_value psl_rt_make_package(psl_value name);
psl_value psl_rt_package_name(psl_value package);
psl_value psl_rt_intern(psl_value package, psl_value name);

psl_value psl_rt_make_closure(psl_closure_code code, psl_value environment);
psl_value psl_rt_call_closure(psl_value closure, psl_value argument);

psl_value psl_rt_values2(psl_value first, psl_value second);
psl_value psl_rt_nth_value(size_t index);
size_t psl_rt_value_count(void);

#endif
