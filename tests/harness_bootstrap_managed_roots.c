#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <string.h>
extern psl_value rn_lazy(psl_value), rn_join(uint64_t,psl_value), rn_recursive(uint64_t,psl_value);
extern uint64_t rn_raw(uint64_t,psl_value);
extern double rn_float(psl_value,double);
void rn_collect(void) {psl_rt_collect_precise();}
void rn_check(uint64_t raw, psl_value live) {
 assert(raw && psl_rt_live_objects()==1);
 assert(psl_rt_car(live)==psl_rt_fixnum(42));
}
static psl_value pair(void) {return psl_rt_cons_precise(psl_rt_fixnum(42),PSL_NIL);}
static void empty(void) {psl_rt_collect_precise();assert(psl_rt_live_objects()==0);}
extern psl_value rn_stack(psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value,psl_value), rn_large(void);
extern double rn_mixed(double,psl_value,double,psl_value,double,psl_value,double,psl_value,double,psl_value,double,psl_value,double,psl_value,double,psl_value,double,psl_value);
extern uint64_t rn_loop(void);
static uint64_t steps;
uint64_t rn_step(void) {return ++steps;}
void rn_note(psl_value x) {
 psl_rt_collect_precise();
 assert(psl_rt_live_objects()>=1 && psl_rt_live_objects()<=2);
 assert(psl_rt_car(x)==psl_rt_fixnum(42));
}
void rn_large_check(psl_value first,psl_value last) {
 psl_rt_collect_precise();assert(psl_rt_live_objects()==96);
 assert(psl_rt_car(first)==psl_rt_fixnum(0));assert(psl_rt_car(last)==psl_rt_fixnum(95));
}
#ifdef _WIN32
#include <windows.h>
/* Exercise real OS unwind metadata at every partial prologue position. */
static void large_unwind(void) {
 DWORD64 base=0,address=(DWORD64)(uintptr_t)&rn_large;
 PRUNTIME_FUNCTION entry=RtlLookupFunctionEntry(address,&base,0);
 assert(entry && base+entry->BeginAddress==address);
 const unsigned char *info=(const unsigned char *)(uintptr_t)(base+entry->UnwindData);
 assert((info[0]&7)==1);
 size_t slots=info[2],frame=0;
 for(size_t i=0;i<slots;++i) {
  unsigned op=info[5+2*i]&15,extra=info[5+2*i]>>4;
  if(op==1) {
   if(extra==0) {uint16_t n;memcpy(&n,info+6+2*i,2);frame+=8u*n;++i;}
   else {uint32_t n;assert(extra==1);memcpy(&n,info+6+2*i,4);frame+=n;i+=2;}
  } else if(op==2) frame+=8u*(extra+1);
 }
 assert(frame>=4096 && frame%16==0);
 unsigned char *stack=calloc(1,frame+128);assert(stack);
 DWORD64 initial=((DWORD64)(uintptr_t)(stack+frame+64)&~UINT64_C(15))+8;
 DWORD64 prior=UINT64_C(0x123456780000),pc=UINT64_C(0x234567890000);
 memcpy((void *)(uintptr_t)initial,&pc,8);memcpy((void *)(uintptr_t)(initial-8),&prior,8);
 for(size_t cut=0;cut<=info[1]+1u;++cut) {
  size_t used=0;int set_frame=0;
  for(size_t i=0;i<slots;++i) {
   unsigned offset=info[4+2*i],op=info[5+2*i]&15,extra=info[5+2*i]>>4;
   size_t amount=0;
   if(op==0) amount=8;
   else if(op==1) {
    if(extra==0) {uint16_t n;memcpy(&n,info+6+2*i,2);amount=8u*n;++i;}
    else {uint32_t n;memcpy(&n,info+6+2*i,4);amount=n;i+=2;}
   } else if(op==2) amount=8u*(extra+1);
   if(offset<=cut) {used+=amount;if(op==3)set_frame=1;}
  }
  CONTEXT context;memset(&context,0,sizeof context);
  context.Rip=address+cut;context.Rsp=initial-used;context.Rbp=set_frame?context.Rsp:prior;
  PVOID handler=0;DWORD64 establisher=0;
  RtlVirtualUnwind(UNW_FLAG_NHANDLER,base,context.Rip,entry,&context,&handler,&establisher,0);
  assert(context.Rip==pc && context.Rsp==initial+8 && context.Rbp==prior);
 }
 free(stack);
}
#endif
int main(void) {
#ifdef _WIN32
 large_unwind();
#endif
 psl_value live=pair();assert(rn_lazy(live)==psl_rt_fixnum(42));empty();
 live=pair();assert(rn_join(0,live)==psl_rt_fixnum(42));empty();
 live=pair();assert(rn_join(1,live)==PSL_NIL);empty();
 psl_value dead=pair();live=pair();assert(rn_raw(dead,live)==dead);empty();
 dead=pair();live=pair();double input,output;uint64_t bits=dead,after;
 memcpy(&input,&bits,8);output=rn_float(live,input);memcpy(&after,&output,8);assert(after==bits);empty();
 live=rn_recursive(1200,PSL_NIL);assert(psl_rt_live_objects()==1200);
 for(int64_t i=1;i<=1200;++i) {assert(psl_rt_car(live)==psl_rt_fixnum(i));live=psl_rt_cdr(live);}
 assert(live==PSL_NIL);empty();
 live=pair();psl_value last=pair();
 psl_value stack=rn_stack(live,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,PSL_NIL,last);
 assert(psl_rt_car(stack)==live && psl_rt_car(psl_rt_cdr(stack))==last);empty();
 live=pair();assert(rn_mixed(1,PSL_NIL,2,PSL_NIL,3,PSL_NIL,4,PSL_NIL,5,PSL_NIL,6,PSL_NIL,7,PSL_NIL,8,PSL_NIL,9.25,live)==9.25);empty();
 assert(rn_loop()==42 && steps==4097);empty();
 live=rn_large();assert(psl_rt_car(live)==psl_rt_fixnum(95));empty();return 0;
}
