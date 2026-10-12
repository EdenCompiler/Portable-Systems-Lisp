#include "../runtime/psl_runtime.h"
#include <assert.h>
extern psl_value bs_make(size_t,uint8_t),bs_live(uint64_t,psl_value),bs_pair(void);
extern uint8_t bs_read(psl_value,size_t);
extern void bs_write(psl_value,size_t,uint8_t);
extern uint64_t bs_loop(void);
static uint64_t steps;
uint64_t bs_step(void) {return ++steps;}
void bs_check(uint64_t raw,psl_value live,psl_value string) {
 psl_rt_collect_precise();assert(raw && psl_rt_live_objects()==2);
 assert(psl_rt_car(live)==psl_rt_fixnum(42));
 assert(psl_rt_string_length(string)==257);
 assert(psl_rt_string_byte(string,0)==255 && psl_rt_string_byte(string,256)==65);
}
void bs_note(psl_value s) {
 psl_rt_collect_precise();assert(psl_rt_live_objects()>=1 && psl_rt_live_objects()<=2);
 assert(psl_rt_string_length(s)==7 && psl_rt_string_byte(s,0)==255 && psl_rt_string_byte(s,6)==0);
}
static void empty(void) {psl_rt_collect_precise();assert(!psl_rt_live_objects());}
int main(void) {
 psl_value s=bs_make(0,0);assert(psl_rt_string_length(s)==0);empty();
 s=bs_make(129,255);assert(bs_read(s,0)==255 && bs_read(s,128)==255);
 bs_write(s,128,0);assert(bs_read(s,128)==0);empty();
 psl_value dead=psl_rt_cons_precise(psl_rt_fixnum(99),PSL_NIL);
 psl_value live=psl_rt_cons_precise(psl_rt_fixnum(42),PSL_NIL);
 s=bs_live(dead,live);assert(psl_rt_string_byte(s,0)==255);empty();
 assert(bs_loop()==42 && steps==4097);empty();
 s=bs_pair();assert(psl_rt_string_length(psl_rt_car(s))==3 && psl_rt_cdr(s)==PSL_NIL);empty();
 return 0;
}
