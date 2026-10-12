#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <string.h>
extern psl_value sp_make(psl_value),sp_name(psl_value),sp_package_name(psl_value),sp_fresh(void),sp_package(void),sp_intern(psl_value,psl_value),sp_graph(void),sp_live(uint64_t,psl_value);
extern uint64_t sp_loop(void);
static uint64_t steps;
uint64_t sp_step(void) {return ++steps;}
static void text(psl_value s,const char *bytes) {
 size_t n=strlen(bytes);assert(psl_rt_string_length(s)==n);
 for(size_t i=0;i<n;++i) assert(psl_rt_string_byte(s,i)==(unsigned char)bytes[i]);
}
static void empty(void) {psl_rt_collect_precise();assert(!psl_rt_live_objects());}
void sp_check(uint64_t raw,psl_value live,psl_value symbol) {
 psl_rt_collect_precise();assert(raw && psl_rt_live_objects()==3);
 assert(psl_rt_car(live)==psl_rt_fixnum(42));text(sp_name(symbol),"Keep");
}
void sp_note(psl_value symbol) {
 psl_rt_collect_precise();assert(psl_rt_live_objects()>=2 && psl_rt_live_objects()<=4);
 text(sp_name(symbol),"loop");
}
static psl_value name(const char *s) {return psl_rt_make_string_from_bytes_precise((uint64_t)(uintptr_t)s,strlen(s));}
int main(void) {
 psl_value pair=sp_fresh(),a=psl_rt_car(pair),b=psl_rt_cdr(pair);
 assert(a!=b && sp_name(a)==sp_name(b));text(sp_name(a),"Case");empty();
 psl_value package=sp_package();text(sp_package_name(package),"Pkg");
 psl_root frame;psl_value roots[3]={package,PSL_NIL,PSL_NIL};psl_rt_push_roots(&frame,roots,3);
 roots[1]=name("Case");roots[2]=sp_intern(package,roots[1]);
 psl_value duplicate=name("Case");assert(roots[2]==sp_intern(package,duplicate));
 psl_value lower=name("case");assert(roots[2]!=sp_intern(package,lower));
 psl_rt_collect_precise();assert(psl_rt_live_objects()==6);
 psl_rt_pop_roots(&frame);empty();
 a=sp_graph();assert(a!=PSL_NIL);psl_rt_push_roots(&frame,&a,1);
 psl_rt_collect_precise();assert(psl_rt_live_objects()==6);text(sp_name(a),"case");
 psl_rt_pop_roots(&frame);empty();
 psl_value dead=psl_rt_cons_precise(psl_rt_fixnum(99),PSL_NIL),live=psl_rt_cons_precise(psl_rt_fixnum(42),PSL_NIL);
 a=sp_live(dead,live);text(sp_name(a),"Keep");empty();
 a=name("Fresh");psl_rt_push_roots(&frame,&a,1);b=sp_make(a);assert(sp_name(b)==a);
 psl_rt_pop_roots(&frame);empty();
 assert(sp_loop()==42 && steps==4097);empty();return 0;
}
