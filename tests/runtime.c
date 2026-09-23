#include "../runtime/psl_runtime.h"

#include <assert.h>
#include <stdint.h>

static psl_value add_environment(psl_value environment, psl_value argument) {
    return psl_rt_fixnum(psl_rt_unbox_fixnum(environment) +
                         psl_rt_unbox_fixnum(argument));
}

static void make_unreachable_objects(void) {
    for (int index = 0; index < 1000; index++) {
        (void)psl_rt_cons(PSL_NIL, PSL_NIL);
    }
}

static void clear_old_stack_words(void) {
    volatile uintptr_t words[2048];
    for (size_t index = 0; index < 2048; index++) {
        words[index] = 0;
    }
    (void)words[0];
}

int main(void) {
    assert(psl_rt_unbox_fixnum(psl_rt_fixnum(-42)) == -42);
    assert(psl_rt_unbox_fixnum(
               psl_rt_fixnum((INT64_C(1) << 62) - 1)) ==
           (INT64_C(1) << 62) - 1);
    assert(psl_rt_unbox_fixnum(
               psl_rt_fixnum(-(INT64_C(1) << 62))) ==
           -(INT64_C(1) << 62));
    assert(psl_rt_truthy(psl_rt_fixnum(0)) == 1);
    assert(psl_rt_truthy(PSL_NIL) == 0);

    psl_value live[5] = {PSL_NIL, PSL_NIL, PSL_NIL, PSL_NIL, PSL_NIL};
    psl_root roots;
    psl_rt_push_roots(&roots, live, 5);

    live[0] = psl_rt_cons(psl_rt_fixnum(42), PSL_NIL);
    assert(psl_rt_kind(live[0]) == PSL_OBJECT_CONS);
    assert(psl_rt_unbox_fixnum(psl_rt_car(live[0])) == 42);
    assert(psl_rt_cdr(live[0]) == PSL_NIL);

    live[1] = psl_rt_make_string(4, 'a');
    psl_rt_string_set_byte(live[1], 1, 'b');
    assert(psl_rt_string_length(live[1]) == 4);
    assert(psl_rt_string_byte(live[1], 1) == 'b');

    live[2] = psl_rt_make_package(live[1]);
    live[3] = psl_rt_intern(live[2], live[1]);
    assert(psl_rt_intern(live[2], live[1]) == live[3]);
    assert(psl_rt_symbol_name(live[3]) == live[1]);
    assert(psl_rt_package_name(live[2]) == live[1]);

    live[4] = psl_rt_make_closure(add_environment, psl_rt_fixnum(30));
    assert(psl_rt_unbox_fixnum(psl_rt_call_closure(
               live[4], psl_rt_fixnum(12))) == 42);
    assert(psl_rt_values2(live[0], live[3]) == live[0]);
    assert(psl_rt_value_count() == 2);
    assert(psl_rt_nth_value(1) == live[3]);

    make_unreachable_objects();
    clear_old_stack_words();
    size_t before = psl_rt_live_objects();
    psl_rt_collect();
    assert(psl_rt_live_objects() < before);
    assert(psl_rt_unbox_fixnum(psl_rt_car(live[0])) == 42);
    assert(psl_rt_symbol_name(live[3]) == live[1]);

    psl_rt_pop_roots(&roots);
    return 0;
}
