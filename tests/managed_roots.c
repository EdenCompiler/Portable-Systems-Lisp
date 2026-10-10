#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <stdint.h>
struct root_pair { uint64_t integer; double floating; };
extern uint64_t root_probe(uint64_t, psl_value, uint64_t);
extern psl_value root_build(psl_value, uint64_t);
extern double root_float(psl_value, double);
extern struct root_pair root_aggregate(psl_value, struct root_pair);
extern psl_value root_join(uint64_t);
extern psl_value root_stack(psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,
                           psl_value,psl_value,psl_value,psl_value,psl_value,psl_value);
extern psl_value root_leaf(psl_value);
extern psl_value root_free(psl_value);
psl_value root_cons(psl_value first, psl_value rest) {
    return psl_rt_cons_precise(first, rest);
}
void root_collect(void) { psl_rt_collect_precise(); }
uint64_t root_check(psl_value live, psl_value local, uint64_t raw) {
    psl_rt_collect_precise();
    assert(psl_rt_live_objects() == 2);
    assert(psl_rt_unbox_fixnum(psl_rt_car(live)) == 40);
    assert(psl_rt_unbox_fixnum(psl_rt_car(local)) == 42);
    return raw;
}
extern uint64_t root_loop(void);
extern psl_value root_large(void);
static uint64_t steps;
uint64_t root_step(void) { return ++steps; }
void root_note(psl_value value) {
    psl_rt_collect_precise();
    assert(psl_rt_live_objects() >= 1 && psl_rt_live_objects() <= 2);
    assert(psl_rt_unbox_fixnum(psl_rt_car(value)) == 42);
}
void root_large_check(psl_value first, psl_value last) {
    psl_rt_collect_precise();
    assert(psl_rt_live_objects() == 96);
    assert(psl_rt_unbox_fixnum(psl_rt_car(first)) == 0);
    assert(psl_rt_unbox_fixnum(psl_rt_car(last)) == 95);
}
static void empty(void) {
    psl_rt_collect_precise();
    assert(psl_rt_live_objects() == 0);
}
int main(void) {
    psl_value garbage = root_cons(psl_rt_fixnum(99), PSL_NIL);
    psl_value live = root_cons(psl_rt_fixnum(40), PSL_NIL);
    assert(root_probe(garbage, live, 42) == garbage);
    empty();
    live = root_cons(psl_rt_fixnum(40), PSL_NIL);
    assert(root_float(live, 3.25) == 3.25);
    empty();
    live = root_cons(psl_rt_fixnum(40), PSL_NIL);
    struct root_pair pair = root_aggregate(live, (struct root_pair){42, 6.5});
    assert(pair.integer == 42 && pair.floating == 6.5);
    empty();
    for (uint64_t flag = 0; flag < 2; ++flag) {
        psl_value joined = root_join(flag);
        assert(psl_rt_live_objects() == 1);
        assert(psl_rt_unbox_fixnum(psl_rt_car(joined)) == (flag ? 42 : 40));
        empty();
    }
    psl_value first = root_cons(psl_rt_fixnum(40), PSL_NIL);
    psl_value last = root_cons(psl_rt_fixnum(42), PSL_NIL);
    psl_value stack = root_stack(first,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,
                                PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,last);
    assert(psl_rt_car(stack) == first && psl_rt_car(psl_rt_cdr(stack)) == last);
    assert(root_leaf(stack) == stack && root_free(stack) == stack);
    empty();
    psl_value list = root_build(PSL_NIL, 1200);
    assert(psl_rt_live_objects() == 1200);
    for (int64_t i = 1; i <= 1200; ++i) {
        assert(psl_rt_unbox_fixnum(psl_rt_car(list)) == i);
        list = psl_rt_cdr(list);
    }
    assert(list == PSL_NIL);
    empty();
    assert(root_loop() == 42 && steps == 4097);
    empty();
    psl_value large = root_large();
    assert(psl_rt_unbox_fixnum(psl_rt_car(large)) == 95);
    empty();
    return 0;
}
