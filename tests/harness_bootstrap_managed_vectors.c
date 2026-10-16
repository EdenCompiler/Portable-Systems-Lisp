#include "../runtime/psl_runtime.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern uint64_t vector_round_trip(psl_value initial, psl_value item);
extern uint64_t vector_noalloc_read(psl_value vector, size_t index,
                                    psl_value expected);
extern psl_value vector_noalloc_set(psl_value vector, size_t index,
                                    psl_value item);
extern psl_value vector_build(int64_t count);

int main(void) {
    psl_value roots_values[4] = {PSL_NIL, PSL_NIL, PSL_NIL, PSL_NIL};
    psl_root roots;
    psl_rt_push_roots(&roots, roots_values, 4);

    roots_values[1] = psl_rt_make_string_precise(3, 'x');
    roots_values[2] = psl_rt_cons_precise(roots_values[1], PSL_NIL);
    assert(vector_round_trip(roots_values[2], roots_values[1]) == 0);
    psl_rt_collect_precise();

    roots_values[0] = psl_rt_make_value_vector_precise(3, PSL_NIL);
    assert(psl_rt_value_vector_set(roots_values[0], 1, roots_values[1]) ==
           roots_values[1]);
    assert(vector_noalloc_read(roots_values[0], 1, roots_values[1]) == 0);
    assert(vector_noalloc_set(roots_values[0], 2, roots_values[2]) ==
           roots_values[2]);
    assert(psl_rt_value_vector_ref(roots_values[0], 2) == roots_values[2]);

    roots_values[3] = vector_build(1024);
    psl_rt_collect_precise();
    assert(psl_rt_value_vector_length(roots_values[3]) == 1024);
    for (size_t index = 0; index < 1024; index++) {
        psl_value item = psl_rt_value_vector_ref(roots_values[3], index);
        assert(psl_rt_unbox_fixnum(psl_rt_car(item)) == (int64_t)(1024-index));
        assert(psl_rt_cdr(item) == PSL_NIL);
    }
    psl_rt_collect_precise();
    assert(psl_rt_value_vector_ref(roots_values[0], 2) == roots_values[2]);

    psl_rt_pop_roots(&roots);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects() == 0);
    puts("Compiled VALUE-vector calls preserve ABI, effects, roots and contents");
    return 0;
}
