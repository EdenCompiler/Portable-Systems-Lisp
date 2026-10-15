#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
extern psl_value nc_identity(psl_value),nc_unused_machine(psl_value);
extern psl_value nc_make(psl_value,psl_value,psl_value,psl_value);
extern psl_value nc_call(psl_value,psl_value),nc_collected(psl_value,psl_value);
extern psl_value nc_shadow(psl_value,psl_value),nc_parallel(void);
extern psl_value nc_reserved_parameter(psl_value,psl_value);
extern psl_value nc_macro_capture(psl_value,psl_value);
extern psl_value nc_nested(psl_value,psl_value,psl_value);
extern psl_value nc_local_shadow(psl_value,psl_value,psl_value);
void nc_collect(void) { psl_rt_collect_precise(); }
static void text(psl_value value,const char *expected) {
 size_t length=0;while(expected[length])++length;
 assert(psl_rt_string_length(value)==length);
 for(size_t i=0;i<length;++i)assert(psl_rt_string_byte(value,i)==(uint8_t)expected[i]);
}
int main(void) {
 psl_value roots[8]={PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL};
 psl_root frame;psl_rt_push_roots(&frame,roots,8);
 for(unsigned i=0;i<4;++i)roots[i]=psl_rt_make_string_precise(i+1,0x80+i);
 assert(nc_identity(roots[0])==roots[0]);assert(nc_unused_machine(roots[1])==roots[1]);
 assert(nc_shadow(roots[0],roots[1])==roots[1]);
 roots[5]=nc_reserved_parameter(roots[0],roots[1]);
 assert(psl_rt_car(roots[5])==roots[0]);assert(psl_rt_cdr(roots[5])==roots[1]);
 roots[5]=nc_macro_capture(roots[1],roots[2]);
 assert(psl_rt_car(roots[5])==roots[1]);assert(psl_rt_cdr(roots[5])==roots[2]);
 roots[4]=nc_make(roots[0],roots[1],roots[2],roots[3]);psl_rt_collect_precise();
 roots[5]=nc_call(roots[4],psl_rt_fixnum(37));
 psl_value list=roots[5];for(unsigned i=0;i<4;++i) {assert(psl_rt_car(list)==roots[i]);list=psl_rt_cdr(list);}
 assert(psl_rt_unbox_fixnum(list)==37);
 roots[5]=nc_collected(roots[2],roots[3]);
 assert(psl_rt_car(roots[5])==roots[2]);assert(psl_rt_cdr(roots[5])==roots[3]);
 roots[5]=nc_parallel();text(psl_rt_car(roots[5]),"inner");text(psl_rt_car(psl_rt_cdr(roots[5])),"outer");
 roots[5]=nc_local_shadow(roots[0],roots[1],roots[2]);
 assert(psl_rt_car(roots[5])==roots[1]);assert(psl_rt_car(psl_rt_cdr(roots[5]))==roots[0]);
 assert(psl_rt_cdr(psl_rt_cdr(roots[5]))==roots[2]);
 roots[6]=nc_nested(roots[0],roots[1],roots[2]);psl_rt_collect_precise();
 roots[7]=nc_call(roots[6],roots[3]);
 assert(psl_rt_car(psl_rt_car(roots[7]))==roots[2]);assert(psl_rt_cdr(psl_rt_car(roots[7]))==roots[0]);
 assert(psl_rt_car(psl_rt_cdr(roots[7]))==roots[1]);assert(psl_rt_cdr(psl_rt_cdr(roots[7]))==roots[3]);
 for(unsigned i=0;i<4096;++i) {
  roots[6]=nc_nested(roots[0],roots[1],roots[2]);roots[7]=nc_call(roots[6],roots[3]);
  assert(psl_rt_cdr(psl_rt_cdr(roots[7]))==roots[3]);
 }
 for(unsigned i=0;i<8;++i)roots[i]=PSL_NIL;
 psl_rt_collect_precise();assert(psl_rt_live_objects()==0);psl_rt_pop_roots(&frame);
 return 0;
}
