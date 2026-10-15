#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>
struct fa_single {float number;};
struct fa_double {double number;};
struct fa_pair {float first,second;};
struct fa_nested {struct fa_pair pair;float third;};
struct fa_two {double first,second;};
struct fa_mixed {uint64_t tag;double number;};
struct fa_narrow {int8_t tag;float number;};
struct fa_four {float a,b,c,d;};
struct fa_varied {struct fa_pair pair;double number;};
uint64_t fa_clobber_c(void) {return UINT64_C(0xdeadbeef01234567);}
extern struct fa_single fa_single_copy(struct fa_single);
extern struct fa_double fa_double_copy(struct fa_double),fa_raw(struct fa_double);
extern struct fa_pair fa_pair_copy(struct fa_pair);
extern struct fa_nested fa_nested_copy(struct fa_nested),fa_roots(struct fa_nested,double,struct fa_narrow,psl_value);
extern struct fa_two fa_two_copy(struct fa_two),fa_join(int,struct fa_two,struct fa_two);
extern struct fa_narrow fa_narrow_copy(struct fa_narrow);
extern struct fa_varied fa_varied_copy(struct fa_varied);
extern struct fa_two fa_partial(double,double,double,double,double,double,double,struct fa_two,double,uint64_t);
extern struct fa_mixed fa_gp_full(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,struct fa_mixed,double,uint64_t);
extern struct fa_mixed fa_fp_full(double,double,double,double,double,double,double,double,struct fa_mixed,uint64_t);
extern struct fa_four fa_hfa_partial(double,double,double,double,double,double,struct fa_four,float,uint64_t);
static uint32_t bits32(float number) {uint32_t bits;memcpy(&bits,&number,4);return bits;}
static uint64_t bits64(double number) {uint64_t bits;memcpy(&bits,&number,8);return bits;}
static float number32(uint32_t bits) {float number;memcpy(&number,&bits,4);return number;}
static double number64(uint64_t bits) {double number;memcpy(&number,&bits,8);return number;}
static void check_payloads(void) {
 static const uint32_t payload32[]={0,UINT32_C(0x80000000),UINT32_C(0x3f800000),UINT32_C(0x7f800000),UINT32_C(0xff800000),UINT32_C(0x7fc12345)};
 static const uint64_t payload64[]={0,UINT64_C(0x8000000000000000),UINT64_C(0x3ff0000000000000),UINT64_C(0x7ff0000000000000),UINT64_C(0xfff0000000000000),UINT64_C(0x7ff8123456789abc)};
 for(unsigned i=0;i<6;++i) {
  struct fa_single s=fa_single_copy((struct fa_single){number32(payload32[i])});assert(bits32(s.number)==payload32[i]);
  struct fa_double d=fa_double_copy((struct fa_double){number64(payload64[i])});assert(bits64(d.number)==payload64[i]);
  struct fa_pair p=fa_pair_copy((struct fa_pair){number32(payload32[i]),number32(payload32[5-i])});
  assert(bits32(p.first)==payload32[i] && bits32(p.second)==payload32[5-i]);
  struct fa_nested n=fa_nested_copy((struct fa_nested){p,number32(payload32[2])});
  assert(bits32(n.pair.first)==payload32[i] && bits32(n.pair.second)==payload32[5-i] && bits32(n.third)==payload32[2]);
  struct fa_two t={number64(payload64[i]),number64(payload64[5-i])},u={2.25,3.5};
  struct fa_two r=fa_two_copy(t);assert(bits64(r.first)==payload64[i] && bits64(r.second)==payload64[5-i]);
  r=fa_join(0,t,u);assert(bits64(r.first)==payload64[i] && bits64(r.second)==payload64[5-i]);
  r=fa_join(1,t,u);assert(r.first==2.25 && r.second==3.5);
  struct fa_narrow q=fa_narrow_copy((struct fa_narrow){INT8_MIN,number32(payload32[i])});assert(q.tag==INT8_MIN && bits32(q.number)==payload32[i]);
  struct fa_varied v=fa_varied_copy((struct fa_varied){p,number64(payload64[i])});
  assert(bits32(v.pair.first)==payload32[i] && bits32(v.pair.second)==payload32[5-i] && bits64(v.number)==payload64[i]);
 }
}
struct fa_two fa_partial_c(double a,double b,double c,double d,double e,double f,double g,struct fa_two x,double tail,uint64_t mark) {
 assert(a==1 && b==2 && c==3 && d==4 && e==5 && f==6 && g==7 && tail==33.5 && mark==UINT64_C(0xfedcba9876543210));
 assert(x.first==2.25 && bits64(x.second)==UINT64_C(0x8000000000000000));x.first+=tail;return x;
}
struct fa_mixed fa_gp_full_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,struct fa_mixed x,double tail,uint64_t mark) {
 assert(a==1 && b==2 && c==3 && d==4 && e==5 && f==6 && tail==33.5 && mark==37);assert(x.tag==UINT64_C(0x8000000000000001) && x.number==2.25);
 x.tag+=37;x.number+=tail;return x;
}
struct fa_mixed fa_fp_full_c(double a,double b,double c,double d,double e,double f,double g,double h,struct fa_mixed x,uint64_t mark) {
 assert(a==1 && b==2 && c==3 && d==4 && e==5 && f==6 && g==7 && h==8 && mark==37);assert(x.tag==UINT64_C(0x8000000000000001) && x.number==2.25);
 x.tag+=37;x.number+=33.5;return x;
}
struct fa_four fa_hfa_partial_c(double a,double b,double c,double d,double e,double f,struct fa_four x,float tail,uint64_t mark) {
 assert(a==1 && b==2 && c==3 && d==4 && e==5 && f==6 && tail==33.5f && mark==37);
 assert(x.a==1.25f && x.b==2.5f && x.c==-3.75f && x.d==4.0f);x.a+=tail;return x;
}
static void check_exhaustion(void) {
 struct fa_two x={2.25,number64(UINT64_C(0x8000000000000000))};struct fa_two r=fa_partial(1,2,3,4,5,6,7,x,33.5,UINT64_C(0xfedcba9876543210));
 assert(r.first==35.75 && bits64(r.second)==UINT64_C(0x8000000000000000));
 struct fa_mixed m={UINT64_C(0x8000000000000001),2.25};struct fa_mixed n=fa_gp_full(1,2,3,4,5,6,m,33.5,37);
 assert(n.tag==m.tag+37 && n.number==35.75);n=fa_fp_full(1,2,3,4,5,6,7,8,m,37);assert(n.tag==m.tag+37 && n.number==35.75);
 struct fa_four q=fa_hfa_partial(1,2,3,4,5,6,(struct fa_four){1.25f,2.5f,-3.75f,4.0f},33.5f,37);
 assert(q.a==34.75f && q.b==2.5f && q.c==-3.75f && q.d==4.0f);
}
struct fa_nested fa_root_check_c(struct fa_nested x,double scale,struct fa_narrow y,psl_value live) {
 psl_rt_collect_precise();assert(psl_rt_live_objects()==1 && psl_rt_string_length(live)==3 && psl_rt_string_byte(live,1)==0x80);
 assert(scale==1.25 && y.tag==INT8_MIN && y.number==7.5f);assert(x.pair.first==2.25f && x.pair.second==-3.5f && x.third==4.75f);return x;
}
struct fa_double fa_raw_check_c(struct fa_double x) {psl_rt_collect_precise();assert(!psl_rt_live_objects());return x;}
static void check_roots(void) {
 psl_value live=psl_rt_make_string_precise(3,0x80);
 struct fa_nested x=fa_roots((struct fa_nested){{2.25f,-3.5f},4.75f},1.25,(struct fa_narrow){INT8_MIN,7.5f},live);
 assert(x.pair.first==2.25f && x.pair.second==-3.5f && x.third==4.75f);psl_rt_collect_precise();assert(!psl_rt_live_objects());
 psl_value raw=psl_rt_make_string_precise(3,0x80);struct fa_double r=fa_raw((struct fa_double){number64((uint64_t)raw)});
 assert(bits64(r.number)==(uint64_t)raw && !psl_rt_live_objects());
}
int main(void) {check_payloads();check_exhaustion();check_roots();return 0;}
