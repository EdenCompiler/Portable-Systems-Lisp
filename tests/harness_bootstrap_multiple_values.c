#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <string.h>
extern psl_value vm_first(psl_value,psl_value),vm_second(psl_value,psl_value),vm_live(void);
extern int64_t vm_order(void),vm_nested(void),vm_outer(void);
extern uint64_t vm_loop(void);
static uint64_t order,steps;
psl_value mv_order(uint64_t which) {assert(which==++order);return psl_rt_fixnum(which==1?19:23);}
void mv_collect(void) {psl_rt_collect_precise();}
uint64_t mv_step(void) {return ++steps;}
static void text(psl_value s,const char *bytes) {
 size_t n=strlen(bytes);assert(psl_rt_string_length(s)==n);
 for(size_t i=0;i<n;++i) assert(psl_rt_string_byte(s,i)==(unsigned char)bytes[i]);
}
void mv_note(psl_value a,psl_value b) {
 psl_rt_collect_precise();assert(psl_rt_live_objects()>=2 && psl_rt_live_objects()<=4);
 text(a,"first");text(b,"second");
}
static void empty(void) {
 psl_rt_values2(PSL_NIL,PSL_NIL);psl_rt_collect_precise();assert(!psl_rt_live_objects());
}
int main(void) {
 assert(!psl_rt_value_count() && psl_rt_nth_value(0)==PSL_NIL);
 assert(vm_first(psl_rt_fixnum(19),PSL_TRUE)==psl_rt_fixnum(19));
 assert(psl_rt_value_count()==2 && psl_rt_nth_value(1)==PSL_TRUE);empty();
 assert(vm_second(PSL_NIL,PSL_TRUE)==PSL_TRUE);empty();
 assert(vm_order()==42 && order==2);empty();assert(vm_nested()==42);empty();
 assert(vm_outer()==42);empty();
 psl_value pair=vm_live();psl_root frame;psl_rt_push_roots(&frame,&pair,1);
 psl_rt_collect_precise();text(psl_rt_car(pair),"first");text(psl_rt_cdr(pair),"second");
 assert(psl_rt_live_objects()==4);psl_rt_pop_roots(&frame);empty();
 assert(vm_loop()==42 && steps==4097);empty();return 0;
}
