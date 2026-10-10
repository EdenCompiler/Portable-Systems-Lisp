#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <stdio.h>
#ifdef PSL_RUNTIME_LINK_PROBE
extern uint64_t add42(uint64_t);
#endif
int main(void) {
#ifdef PSL_RUNTIME_LINK_PROBE
    assert(add42(0)==42);
#endif
    volatile psl_value unregistered=psl_rt_cons(psl_rt_fixnum(1),PSL_NIL);
    assert(psl_rt_live_objects()==1);
    psl_rt_collect();
    assert(psl_rt_live_objects()==1);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects()==0);
    unregistered=PSL_NIL;
    assert(unregistered==PSL_NIL);
    psl_value values[2]={PSL_NIL,PSL_NIL};
    psl_root roots;
    psl_rt_push_roots(&roots,values,2);
    for(unsigned i=0;i<512;++i) {
        values[0]=psl_rt_cons_precise(psl_rt_fixnum(i),values[0]);
    }
    assert(psl_rt_live_objects()==512);
    for(unsigned i=0;i<100;++i)
        (void)psl_rt_cons_precise(psl_rt_fixnum(i),PSL_NIL);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects()==512);
    values[1]=psl_rt_cons_precise(values[0],values[0]);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects()==513);
    assert(psl_rt_car(values[1])==values[0] && psl_rt_cdr(values[1])==values[0]);
    psl_value cursor=values[0];
    for(unsigned i=512;i>0;--i) {
        assert(psl_rt_unbox_fixnum(psl_rt_car(cursor))==i-1);
        cursor=psl_rt_cdr(cursor);
    }
    assert(cursor==PSL_NIL);
    unsigned automatic=0;
    for(unsigned i=0;i<4096;++i) {
        size_t count=psl_rt_live_objects();
        psl_value temporary=psl_rt_cons_precise(psl_rt_fixnum(i),PSL_NIL);
        values[1]=psl_rt_cons_precise(temporary,values[0]);
        values[0]=psl_rt_cons_precise(psl_rt_fixnum(i),values[0]);
        assert(psl_rt_unbox_fixnum(psl_rt_car(psl_rt_car(values[1])))==i);
        if(psl_rt_live_objects()<count+3) automatic++;
    }
    assert(automatic>0);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects()==512+4096+2);
    psl_rt_pop_roots(&roots);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects()==0);
    puts("explicit runtime roots preserve shared lists through precise/automatic collection and release unregistered values");
}
