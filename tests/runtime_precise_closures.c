#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <stdint.h>
static psl_value callback(psl_value environment,psl_value argument) {
 psl_rt_collect_precise();
 assert(psl_rt_string_length(environment)==3);
 assert(psl_rt_string_byte(environment,1)==0x80);
 assert(psl_rt_unbox_fixnum(argument)==37);
 return psl_rt_cons_precise(environment,argument);
}
static void invoke(psl_value closure,psl_value *result) {
 *result=psl_rt_call_closure(closure,psl_rt_fixnum(37));
 assert(psl_rt_string_length(psl_rt_car(*result))==3);
 assert(psl_rt_string_byte(psl_rt_car(*result),1)==0x80);
 assert(psl_rt_unbox_fixnum(psl_rt_cdr(*result))==37);
}
int main(void) {
 psl_value roots[2]={PSL_NIL,PSL_NIL};psl_root frame;
 psl_rt_push_roots(&frame,roots,2);
 roots[0]=psl_rt_make_string_precise(3,0x80);
 roots[0]=psl_rt_make_closure_precise(callback,roots[0]);
 psl_rt_collect_precise();assert(psl_rt_live_objects()==2);
 invoke(roots[0],&roots[1]);psl_rt_collect_precise();assert(psl_rt_live_objects()==3);
 roots[1]=PSL_NIL;
 for(unsigned i=0;i<4096;++i) {
  roots[1]=psl_rt_make_closure_precise(callback,psl_rt_car(psl_rt_call_closure(roots[0],psl_rt_fixnum(37))));
  invoke(roots[1],&roots[1]);
 }
 roots[0]=roots[1]=PSL_NIL;psl_rt_collect_precise();assert(!psl_rt_live_objects());
 psl_rt_pop_roots(&frame);
 return 0;
}
