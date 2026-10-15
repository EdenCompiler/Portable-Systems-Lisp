#include <stdint.h>
#include <assert.h>
#include "../runtime/psl_runtime.h"
struct wide { uint64_t first, second; };
struct triple { uint32_t first, second, third; };
struct wide wide_bump_c(struct wide x) { x.first+=9; x.second^=UINT64_C(0xdeadbeef82345678); return x; }
struct triple triple_bump_c(struct triple x) { x.first+=19; x.second+=23; x.third+=42; return x; }
struct wide wide_stack_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,struct wide x,uint64_t tail) { assert(a==1 && b==2 && c==3 && d==4 && e==5 && tail==UINT64_C(0xfedcba9876543210)); x.first+=a+b+c+d+e; x.second^=tail; return x; }
struct wide wide_root_check_c(struct wide x,psl_value live) { psl_rt_collect_precise(); assert(psl_rt_string_length(live)==3 && psl_rt_string_byte(live,1)==0x80 && psl_rt_live_objects()==1); x.first+=7; return x; }
struct wide ia_raw_collect_c(struct wide x) { psl_rt_collect_precise(); assert(!psl_rt_live_objects()); return x; }
extern struct wide wide_bump(struct wide), wide_nested(struct wide);
extern struct triple triple_bump(struct triple);
extern struct wide wide_stack(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,struct wide,uint64_t);
extern struct wide wide_choose(int,struct wide,struct wide),wide_managed(struct wide,psl_value);
extern struct wide ia_raw_collect(struct wide);
extern struct wide wide_split(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,struct wide,uint64_t);
struct wide wide_split_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,struct wide x,uint64_t tail) { assert(a==1 && b==2 && c==3 && d==4 && e==5 && f==6 && g==7 && tail==99); x.first+=28; x.second^=99; return x; }
static void check_wide(void) {
 struct wide x={UINT64_C(0xfedcba9876543210),UINT64_C(0x8000000000000001)};
 struct wide r=wide_bump(x); assert(r.first==x.first+9 && r.second==(x.second^UINT64_C(0xdeadbeef82345678)));
 r=wide_nested(x); assert(r.first==x.first+18 && r.second==x.second);
 r=wide_stack(1,2,3,4,5,x,UINT64_C(0xfedcba9876543210)); assert(r.first==x.first+15 && r.second==(x.second^UINT64_C(0xfedcba9876543210)));
 r=wide_split(1,2,3,4,5,6,7,x,99); assert(r.first==x.first+28 && r.second==(x.second^99));
 struct wide y={19,23}; r=wide_choose(0,x,y); assert(r.first==x.first && r.second==x.second); r=wide_choose(1,x,y); assert(r.first==19 && r.second==23);
 struct triple t=triple_bump((struct triple){UINT32_MAX-7,17,99}); assert(t.first==11 && t.second==40 && t.third==141);
 psl_value live=psl_rt_make_string_precise(3,0x80); r=wide_managed(x,live); assert(r.first==x.first+7 && r.second==x.second); psl_rt_collect_precise(); assert(!psl_rt_live_objects());

}
static void check_raw_payload(void) {
 psl_value raw=psl_rt_make_string_precise(3,0x80);
 struct wide x={(uint64_t)raw,(uint64_t)raw & ~UINT64_C(7)};
 struct wide result=ia_raw_collect(x);
 assert(result.first==x.first && result.second==x.second);
 assert(!psl_rt_live_objects());
}

#include <assert.h>
#include <stdint.h>
struct little { uint8_t a,b,c; };
struct little little_bump_c(struct little x) { x.a+=19; x.b+=23; x.c+=42; return x; }
void little_mutate_c(struct little x) { volatile struct little *p=&x; p->a=99; p->b=98; p->c=97; }
uint64_t little_score_c(struct little x) { return x.a+256u*x.b+65536u*x.c; }
extern struct little little_bump(struct little);
extern uint64_t little_survives(struct little);

struct bytes3 { uint8_t b0; uint8_t b1; uint8_t b2; };
extern struct bytes3 ia_bump_bytes3(struct bytes3);
extern uint64_t ia_keep_bytes3(struct bytes3);
struct bytes3 ia_bump_bytes3_c(struct bytes3 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<3;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes3_c(struct bytes3 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<3;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes3_c(struct bytes3 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<3;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes3(void) { struct bytes3 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<3;++i) p[i]=(unsigned char)(250-i); struct bytes3 y=ia_bump_bytes3(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<3;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes3(x)==ia_score_bytes3_c(x)); }
struct bytes5 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; };
extern struct bytes5 ia_bump_bytes5(struct bytes5);
extern uint64_t ia_keep_bytes5(struct bytes5);
struct bytes5 ia_bump_bytes5_c(struct bytes5 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<5;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes5_c(struct bytes5 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<5;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes5_c(struct bytes5 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<5;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes5(void) { struct bytes5 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<5;++i) p[i]=(unsigned char)(250-i); struct bytes5 y=ia_bump_bytes5(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<5;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes5(x)==ia_score_bytes5_c(x)); }
struct bytes6 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; };
extern struct bytes6 ia_bump_bytes6(struct bytes6);
extern uint64_t ia_keep_bytes6(struct bytes6);
struct bytes6 ia_bump_bytes6_c(struct bytes6 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<6;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes6_c(struct bytes6 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<6;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes6_c(struct bytes6 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<6;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes6(void) { struct bytes6 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<6;++i) p[i]=(unsigned char)(250-i); struct bytes6 y=ia_bump_bytes6(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<6;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes6(x)==ia_score_bytes6_c(x)); }
struct bytes7 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; uint8_t b6; };
extern struct bytes7 ia_bump_bytes7(struct bytes7);
extern uint64_t ia_keep_bytes7(struct bytes7);
struct bytes7 ia_bump_bytes7_c(struct bytes7 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<7;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes7_c(struct bytes7 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<7;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes7_c(struct bytes7 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<7;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes7(void) { struct bytes7 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<7;++i) p[i]=(unsigned char)(250-i); struct bytes7 y=ia_bump_bytes7(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<7;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes7(x)==ia_score_bytes7_c(x)); }
struct bytes9 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; uint8_t b6; uint8_t b7; uint8_t b8; };
extern struct bytes9 ia_bump_bytes9(struct bytes9);
extern uint64_t ia_keep_bytes9(struct bytes9);
struct bytes9 ia_bump_bytes9_c(struct bytes9 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<9;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes9_c(struct bytes9 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<9;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes9_c(struct bytes9 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<9;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes9(void) { struct bytes9 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<9;++i) p[i]=(unsigned char)(250-i); struct bytes9 y=ia_bump_bytes9(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<9;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes9(x)==ia_score_bytes9_c(x)); }
struct bytes10 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; uint8_t b6; uint8_t b7; uint8_t b8; uint8_t b9; };
extern struct bytes10 ia_bump_bytes10(struct bytes10);
extern uint64_t ia_keep_bytes10(struct bytes10);
struct bytes10 ia_bump_bytes10_c(struct bytes10 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<10;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes10_c(struct bytes10 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<10;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes10_c(struct bytes10 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<10;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes10(void) { struct bytes10 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<10;++i) p[i]=(unsigned char)(250-i); struct bytes10 y=ia_bump_bytes10(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<10;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes10(x)==ia_score_bytes10_c(x)); }
struct bytes11 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; uint8_t b6; uint8_t b7; uint8_t b8; uint8_t b9; uint8_t b10; };
extern struct bytes11 ia_bump_bytes11(struct bytes11);
extern uint64_t ia_keep_bytes11(struct bytes11);
struct bytes11 ia_bump_bytes11_c(struct bytes11 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<11;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes11_c(struct bytes11 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<11;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes11_c(struct bytes11 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<11;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes11(void) { struct bytes11 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<11;++i) p[i]=(unsigned char)(250-i); struct bytes11 y=ia_bump_bytes11(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<11;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes11(x)==ia_score_bytes11_c(x)); }
struct bytes13 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; uint8_t b6; uint8_t b7; uint8_t b8; uint8_t b9; uint8_t b10; uint8_t b11; uint8_t b12; };
extern struct bytes13 ia_bump_bytes13(struct bytes13);
extern uint64_t ia_keep_bytes13(struct bytes13);
struct bytes13 ia_bump_bytes13_c(struct bytes13 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<13;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes13_c(struct bytes13 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<13;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes13_c(struct bytes13 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<13;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes13(void) { struct bytes13 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<13;++i) p[i]=(unsigned char)(250-i); struct bytes13 y=ia_bump_bytes13(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<13;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes13(x)==ia_score_bytes13_c(x)); }
struct bytes14 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; uint8_t b6; uint8_t b7; uint8_t b8; uint8_t b9; uint8_t b10; uint8_t b11; uint8_t b12; uint8_t b13; };
extern struct bytes14 ia_bump_bytes14(struct bytes14);
extern uint64_t ia_keep_bytes14(struct bytes14);
struct bytes14 ia_bump_bytes14_c(struct bytes14 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<14;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes14_c(struct bytes14 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<14;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes14_c(struct bytes14 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<14;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes14(void) { struct bytes14 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<14;++i) p[i]=(unsigned char)(250-i); struct bytes14 y=ia_bump_bytes14(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<14;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes14(x)==ia_score_bytes14_c(x)); }
struct bytes15 { uint8_t b0; uint8_t b1; uint8_t b2; uint8_t b3; uint8_t b4; uint8_t b5; uint8_t b6; uint8_t b7; uint8_t b8; uint8_t b9; uint8_t b10; uint8_t b11; uint8_t b12; uint8_t b13; uint8_t b14; };
extern struct bytes15 ia_bump_bytes15(struct bytes15);
extern uint64_t ia_keep_bytes15(struct bytes15);
struct bytes15 ia_bump_bytes15_c(struct bytes15 x) { unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<15;++i) p[i]=(unsigned char)(p[i]+i+7); return x; }
void ia_mutate_bytes15_c(struct bytes15 x) { volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<15;++i) p[i]=(unsigned char)(99+i); }
uint64_t ia_score_bytes15_c(struct bytes15 x) { const unsigned char *p=(const unsigned char*)&x; uint64_t sum=0; for(unsigned i=0;i<15;++i) sum=sum*257+p[i]; return sum; }
static void check_bytes15(void) { struct bytes15 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<15;++i) p[i]=(unsigned char)(250-i); struct bytes15 y=ia_bump_bytes15(x); const unsigned char *q=(const unsigned char*)&y; for(unsigned i=0;i<15;++i) assert(q[i]==(unsigned char)(p[i]+i+7)); assert(ia_keep_bytes15(x)==ia_score_bytes15_c(x)); }

#ifdef _WIN32
/* Microsoft x64 lowers this source signature to a hidden return pointer and
   an indirect argument pointer. Verify exact extent with canaries after byte3. */
extern void *ia_little_raw(void *,const void *);
static void check_exact_extent(void) {
 _Alignas(16) unsigned char source[16], destination[16];
 for(unsigned i=0;i<16;++i) {source[i]=(unsigned char)(41+i);destination[i]=0xa5;}
 assert(ia_little_raw(destination,source)==destination);
 for(unsigned i=0;i<3;++i) assert(destination[i]==source[i]);
 for(unsigned i=3;i<16;++i) assert(destination[i]==0xa5 && source[i]==41+i);
}
#else
static void check_exact_extent(void) {}
#endif
extern struct wide ia_mixed(struct bytes15,double,struct bytes15,uint64_t,struct wide);
extern struct wide ia_alias(struct bytes15,struct wide),ia_after_mixed(struct bytes15,struct wide);
extern struct wide ia_large_frame(struct wide,psl_value);
static void original(struct bytes15 x) { const unsigned char *p=(const unsigned char*)&x; for(unsigned i=0;i<15;++i) assert(p[i]==250-i); }
void ia_original_c(struct bytes15 x) { original(x); }
struct wide ia_mixed_c(struct bytes15 x,double scale,struct bytes15 y,uint64_t mark,struct wide z) {
 assert(scale==1.25 && mark==37); original(x); original(y);
 volatile unsigned char *p=(volatile unsigned char*)&x; for(unsigned i=0;i<15;++i) p[i]=(unsigned char)(99+i);
 original(y); z.first+=37; z.second^=UINT64_C(0xfedcba9876543210); return z;
}
static void check_mixed_and_frame(void) {
 struct bytes15 x; unsigned char *p=(unsigned char*)&x; for(unsigned i=0;i<15;++i) p[i]=(unsigned char)(250-i);
 struct wide z={UINT64_C(0x8000000000000001),UINT64_C(0x12345678abcdef01)};
 struct wide r=ia_mixed(x,1.25,x,37,z); assert(r.first==z.first+37 && r.second==(z.second^UINT64_C(0xfedcba9876543210)));
 r=ia_alias(x,z); assert(r.first==z.first+37 && r.second==(z.second^UINT64_C(0xfedcba9876543210)));
 r=ia_after_mixed(x,z); assert(r.first==z.first+37 && r.second==(z.second^UINT64_C(0xfedcba9876543210)));
 psl_value live=psl_rt_make_string_precise(3,0x80); r=ia_large_frame(z,live); assert(r.first==z.first && r.second==z.second);
 psl_rt_collect_precise(); assert(!psl_rt_live_objects());
}

#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>
#include <string.h>
static void check_large_unwind(void) {
 DWORD64 image=0; DWORD64 address=(DWORD64)(uintptr_t)ia_large_frame;
 PRUNTIME_FUNCTION fn=RtlLookupFunctionEntry(address,&image,NULL); assert(fn);
 const unsigned char *info=(const unsigned char*)(uintptr_t)(image+fn->UnwindData);
 assert((info[0]&7)==1 && info[1]>0 && info[2]>0);
 size_t allocation=0;
 for(unsigned index=0;index<info[2];++index) {
  const unsigned char *code=info+4+index*2;
  unsigned operation=code[1]&15, detail=code[1]>>4;
  if(operation==1) {
   assert(index+1<info[2]);
   if(detail==0) { allocation+=(size_t)(code[2]|((unsigned)code[3]<<8))*8; ++index; }
   else { assert(detail==1 && index+2<info[2]); allocation+=(size_t)code[2]|((size_t)code[3]<<8)|((size_t)code[4]<<16)|((size_t)code[5]<<24);index+=2; }
  } else if(operation==2) allocation+=8*detail+8;
  else assert(operation==0 || operation==3);
 }
 assert(allocation>=4096);
 unsigned char *stack=malloc(allocation+256);assert(stack);
 uintptr_t entry=(((uintptr_t)stack+allocation+128)&~(uintptr_t)15)+8;
 uintptr_t saved=entry-8, old_bp=UINT64_C(0x1020304050607080),return_address=UINT64_C(0x123456789abcdef0);
 memcpy((void*)entry,&return_address,8);memcpy((void*)saved,&old_bp,8);
 CONTEXT context;memset(&context,0,sizeof context);
 context.Rip=image+fn->BeginAddress+info[1]+4;context.Rsp=saved-allocation;
 context.Rbp=(info[3]&15)?context.Rsp+(info[3]>>4)*16:saved;
 PVOID handler=NULL;DWORD64 establisher=0;
 RtlVirtualUnwind(UNW_FLAG_NHANDLER,image,context.Rip,fn,&context,&handler,&establisher,NULL);
 assert(context.Rip==return_address && context.Rsp==entry+8 && context.Rbp==old_bp);
 free(stack);
}
#else
static void check_large_unwind(void) {}
#endif
int main(void) {
 check_wide(); check_raw_payload(); check_mixed_and_frame(); check_large_unwind();
 struct little x={250,244,215}; struct little y=little_bump(x);
 assert(y.a==13 && y.b==11 && y.c==1 && little_survives(x)==little_score_c(x));
check_bytes3(); check_bytes5(); check_bytes6(); check_bytes7(); check_bytes9(); check_bytes10(); check_bytes11(); check_bytes13(); check_bytes14(); check_bytes15();
 check_exact_extent(); return 0;
}
