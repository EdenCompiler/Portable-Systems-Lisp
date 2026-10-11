#include "../runtime/psl_runtime.h"
#include <assert.h>
extern psl_value mv_identity(psl_value), mv_nil(void), mv_empty_nil(void), mv_true(void);
extern psl_value mv_min(void), mv_max(void), mv_eq_value(psl_value,psl_value), mv_box(int64_t);
extern uint64_t mv_truth(psl_value), mv_zero_truth(void), mv_eq_branch(psl_value,psl_value);
extern int64_t mv_unbox(psl_value);
extern psl_value mv_car(psl_value), mv_cdr(psl_value), mv_recursive(uint64_t,psl_value), mv_locals(psl_value);
extern psl_value mv_stack(psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value);
extern psl_value mv_mixed(psl_value);
psl_value mv_c_mixed(double f0, psl_value v0, double f1, psl_value v1, double f2, psl_value v2, double f3, psl_value v3, double f4, psl_value v4, double f5, psl_value v5, double f6, psl_value v6, double f7, psl_value v7, double f8, psl_value v8) {
    assert(f0 == 1.0);
    assert(f1 == 2.0);
    assert(f2 == 3.0);
    assert(f3 == 4.0);
    assert(f4 == 5.0);
    assert(f5 == 6.0);
    assert(f6 == 7.0);
    assert(f7 == 8.0);
    assert(f8 == 9.0);
    assert(v1 == psl_rt_fixnum(1));
    assert(v2 == psl_rt_fixnum(2));
    assert(v3 == psl_rt_fixnum(3));
    assert(v4 == psl_rt_fixnum(4));
    assert(v5 == psl_rt_fixnum(5));
    assert(v6 == psl_rt_fixnum(6));
    assert(v7 == psl_rt_fixnum(7));
    assert(v0 == v8); return v8;
}
int main(void) {
    const int64_t min = -INT64_C(4611686018427387904), max = INT64_C(4611686018427387903);
    assert(mv_nil()==PSL_NIL && mv_empty_nil()==PSL_NIL && mv_true()==PSL_TRUE);
    assert(mv_min()==psl_rt_fixnum(min) && mv_max()==psl_rt_fixnum(max));
    assert(mv_truth(PSL_NIL)==22 && mv_truth(PSL_TRUE)==11 && mv_truth(psl_rt_fixnum(0))==11);
    assert(mv_zero_truth()==11);
    assert(mv_eq_value(PSL_NIL,PSL_NIL)==PSL_TRUE && mv_eq_value(PSL_NIL,PSL_TRUE)==PSL_NIL);
    assert(mv_eq_branch(PSL_NIL,PSL_NIL)==11 && mv_eq_branch(PSL_NIL,PSL_TRUE)==22);
    assert(mv_unbox(mv_box(-123))==-123 && mv_unbox(mv_box(min))==min && mv_unbox(mv_box(max))==max);
    assert(mv_car(PSL_NIL)==PSL_NIL && mv_cdr(PSL_NIL)==PSL_NIL);
    psl_value pair=psl_rt_cons_precise(psl_rt_fixnum(42),PSL_NIL);
    assert(mv_mixed(pair)==pair);
    assert(mv_identity(pair)==pair && mv_locals(pair)==pair && mv_recursive(200,pair)==pair);
    assert(mv_car(pair)==psl_rt_fixnum(42) && mv_cdr(pair)==PSL_NIL);
    assert(mv_eq_value(pair,pair)==PSL_TRUE && mv_eq_value(pair,PSL_NIL)==PSL_NIL);
    assert(mv_stack(PSL_TRUE,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,pair,psl_rt_fixnum(-8))==psl_rt_fixnum(-8));
    assert(mv_stack(PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,pair,PSL_NIL)==pair);
    psl_rt_collect_precise(); assert(psl_rt_live_objects()==0);
    return 0;
}
