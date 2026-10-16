#include "../runtime/psl_runtime.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

#ifdef PSL_VECTOR_ALLOC_WRAPPERS
static int track_allocations;
static size_t tracked_allocations;
extern void *__real_malloc(size_t size);
extern void *__real_calloc(size_t count, size_t size);
extern void *__real_realloc(void *memory, size_t size);

void *__wrap_malloc(size_t size) {
    if (track_allocations) tracked_allocations++;
    return __real_malloc(size);
}

void *__wrap_calloc(size_t count, size_t size) {
    if (track_allocations) tracked_allocations++;
    return __real_calloc(count, size);
}

void *__wrap_realloc(void *memory, size_t size) {
    if (track_allocations) tracked_allocations++;
    return __real_realloc(memory, size);
}
#endif

static psl_value return_environment(psl_value environment, psl_value argument) {
    (void)argument;
    return environment;
}

static void expect_failure(const char *mode) {
    if (strcmp(mode, "bounds") == 0) {
        psl_value vector = psl_rt_make_value_vector_precise(1, PSL_NIL);
        (void)psl_rt_value_vector_ref(vector, 1);
    } else if (strcmp(mode, "set-bounds") == 0) {
        psl_value vector = psl_rt_make_value_vector_precise(1, PSL_NIL);
        (void)psl_rt_value_vector_set(vector, 1, PSL_TRUE);
    } else if (strcmp(mode, "wrong-kind") == 0) {
        (void)psl_rt_value_vector_length(PSL_NIL);
    } else if (strcmp(mode, "overflow") == 0) {
        (void)psl_rt_make_value_vector_precise(SIZE_MAX, PSL_NIL);
    }
}

int main(int argc, char **argv) {
    if (argc == 2) {
        expect_failure(argv[1]);
        return 0;
    }
    assert(argc == 1);

    psl_value roots_values[4] = {PSL_NIL, PSL_NIL, PSL_NIL, PSL_NIL};
    psl_root roots;
    psl_rt_push_roots(&roots, roots_values, 4);

    roots_values[1] = psl_rt_make_string_precise(5, 'v');
    roots_values[2] = psl_rt_cons_precise(roots_values[1], PSL_NIL);
    roots_values[3] = psl_rt_make_closure(return_environment, roots_values[2]);
    roots_values[0] = psl_rt_make_value_vector_precise(2, roots_values[2]);
    assert(psl_rt_value_vector_length(roots_values[0]) == 2);
    assert(psl_rt_value_vector_ref(roots_values[0], 1) == roots_values[2]);
    assert(psl_rt_value_vector_set(roots_values[0], 1, roots_values[3]) ==
           roots_values[3]);
    psl_value alias = roots_values[0];

    /* The vector, not these C locals, must retain this nested object graph. */
    roots_values[1] = PSL_NIL;
    roots_values[2] = PSL_NIL;
    roots_values[3] = PSL_NIL;
    psl_rt_collect_precise();
    assert(psl_rt_value_vector_ref(roots_values[0], 0) != PSL_NIL);
    psl_value closure = psl_rt_value_vector_ref(alias, 1);
    psl_value nested = psl_rt_call_closure(closure, PSL_TRUE);
    psl_value string = psl_rt_car(nested);
    assert(psl_rt_kind(string) == PSL_OBJECT_STRING);
    assert(psl_rt_string_length(string) == 5);
    assert(psl_rt_string_byte(string, 4) == 'v');

    /* Bring the precise heap exactly to its first collection threshold. The
       next vector growth must collect while both vector and appended value are
       internally rooted. Unregistered garbage is reclaimed at that point. */
    psl_value appended = psl_rt_cons_precise(psl_rt_fixnum(77), PSL_NIL);
    while (psl_rt_live_objects() < 256) {
        (void)psl_rt_cons_precise(psl_rt_fixnum(7), PSL_NIL);
    }
    assert(psl_rt_live_objects() == 256);
    assert(psl_rt_value_vector_push_precise(roots_values[0], appended) == 2);
    assert(psl_rt_live_objects() < 128);
    roots_values[3] = psl_rt_value_vector_ref(alias, 2);
    assert(roots_values[3] == appended);
    assert(psl_rt_unbox_fixnum(
               psl_rt_car(psl_rt_value_vector_ref(alias, 2))) == 77);

#ifdef PSL_VECTOR_ALLOC_WRAPPERS
    psl_value stable_item = psl_rt_value_vector_ref(alias, 0);
    track_allocations = 1;
    assert(psl_rt_value_vector_length(alias) == 3);
    assert(psl_rt_value_vector_ref(alias, 0) == stable_item);
    assert(psl_rt_value_vector_set(alias, 2, PSL_NIL) == PSL_NIL);
    assert(psl_rt_value_vector_set(alias, 2, roots_values[3]) == roots_values[3]);
    track_allocations = 0;
    assert(tracked_allocations == 0);
#endif

    const size_t pushed = 5000;
    for (size_t index = 3; index < pushed; index++) {
        psl_value item = psl_rt_cons_precise(psl_rt_fixnum((int64_t)index),
                                             PSL_NIL);
        assert(psl_rt_value_vector_push_precise(roots_values[0], item) == index);
    }
    assert(roots_values[0] == alias);
    assert(psl_rt_value_vector_length(alias) == pushed);
    assert(psl_rt_unbox_fixnum(
               psl_rt_car(psl_rt_value_vector_ref(alias, pushed - 1))) ==
           (int64_t)(pushed - 1));

    psl_rt_collect_precise();
    assert(psl_rt_unbox_fixnum(
               psl_rt_car(psl_rt_value_vector_ref(alias, 4096))) == 4096);
    psl_rt_pop_roots(&roots);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects() == 0);
    puts("precise VALUE vectors preserve identity, values, growth and collection");
    return 0;
}
