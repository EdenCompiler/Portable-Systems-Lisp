#include "../runtime/psl_runtime.h"
#include <assert.h>
#include <string.h>
extern psl_value sl_utf8(void),sl_empty(void),sl_text(void),sl_same(void),sl_pair(void),sl_zero(void),sl_large(void),sl_live(uint64_t,psl_value),sl_choice(uint64_t);
extern uint64_t sl_loop(void);
static uint64_t steps;
uint64_t sl_step(void) {return ++steps;}
static void text(psl_value s,const unsigned char *bytes,size_t length) {
 assert(psl_rt_string_length(s)==length);
 for(size_t i=0;i<length;++i) assert(psl_rt_string_byte(s,i)==bytes[i]);
}
void sl_check(uint64_t raw,psl_value live,psl_value s) {
 psl_rt_collect_precise();assert(raw && psl_rt_live_objects()==2);
 assert(psl_rt_car(live)==psl_rt_fixnum(42));text(s,(const unsigned char*)"hello",5);
}
void sl_note(psl_value s) {
 psl_rt_collect_precise();assert(psl_rt_live_objects()>=1 && psl_rt_live_objects()<=2);
 text(s,(const unsigned char*)"hello",5);
}
static void empty(void) {psl_rt_collect_precise();assert(!psl_rt_live_objects());}
int main(void) {
 text(sl_empty(),(const unsigned char*)"",0);empty();
 static const unsigned char boundary[]={0xc2,0x80,0xdf,0xbf,0xe0,0xa0,0x80,0xed,0x9f,0xbf,0xee,0x80,0x80,0xef,0xbf,0xbf,0xf0,0x90,0x80,0x80,0xf4,0x8f,0xbf,0xbf};
 text(sl_utf8(),boundary,sizeof boundary);empty();
 static const unsigned char escaped[]={97,34,98,92,99,110,206,187,240,159,152,128,10,90};
 text(sl_text(),escaped,sizeof escaped);empty();
 psl_value a=sl_same();psl_root roots;psl_rt_push_roots(&roots,&a,1);
 psl_rt_string_set_byte(a,0,255);psl_value b=sl_same();assert(a!=b);
 text(b,(const unsigned char*)"hello",5);assert(psl_rt_string_byte(a,0)==255);
 psl_rt_pop_roots(&roots);empty();
 psl_value pair=sl_pair();text(psl_rt_car(pair),(const unsigned char*)"hello",5);
 text(psl_rt_cdr(pair),(const unsigned char*)"world",5);empty();
 const unsigned char zero[]={97,0,98};text(sl_zero(),zero,3);empty();
 a=sl_large();assert(psl_rt_string_length(a)==10000);
 for(size_t i=0;i<10000;++i) {assert(psl_rt_string_byte(a,i)==65+i%26);}
 empty();
 text(sl_choice(1),(const unsigned char*)"hello",5);empty();
 text(sl_choice(0),(const unsigned char*)"world",5);empty();
 psl_value dead=psl_rt_cons_precise(psl_rt_fixnum(99),PSL_NIL);
 psl_value live=psl_rt_cons_precise(psl_rt_fixnum(42),PSL_NIL);
 text(sl_live(dead,live),(const unsigned char*)"hello",5);empty();
 assert(sl_loop()==42 && steps==4097);empty();return 0;
}
