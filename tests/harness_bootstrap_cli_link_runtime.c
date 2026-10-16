#include "../runtime/psl_runtime.h"
#include <stdint.h>
extern uint64_t native_cli_answer(void);
static psl_value answer(psl_value environment, psl_value argument) {
    psl_rt_collect_precise();
    return argument == PSL_NIL ? psl_rt_car(environment) : PSL_NIL;
}
int main(void) {
    psl_value pair = psl_rt_cons_precise(
        psl_rt_fixnum((int64_t)native_cli_answer()), PSL_NIL);
    psl_value closure = psl_rt_make_closure_precise(answer, pair);
    psl_value vector = psl_rt_make_value_vector_precise(1, closure);
    psl_root root;
    psl_rt_push_roots(&root, &vector, 1);
    if (psl_rt_value_vector_push_precise(vector, PSL_NIL) != 1 ||
        psl_rt_value_vector_length(vector) != 2) return 1;
    psl_value result = psl_rt_call_closure(psl_rt_value_vector_ref(vector, 0), PSL_NIL);
    if (psl_rt_value_vector_set(vector, 0, PSL_NIL) != PSL_NIL) return 1;
    psl_rt_pop_roots(&root);
    psl_rt_collect_precise();
    return psl_rt_unbox_fixnum(result) == 42 && !psl_rt_live_objects() ? 0 : 1;
}
