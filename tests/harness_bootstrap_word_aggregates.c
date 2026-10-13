#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
struct byte_record { uint8_t byte; };
struct short_record { int8_t low; uint8_t high; };
struct tiny_record { uint32_t count; };
struct word_record { uint64_t bits; };
struct pair_record { uint32_t first, second; };
struct padded_record { uint8_t tag; uint32_t payload; };
struct pointer_record { void *address; };
struct inner_record { uint16_t first, second; };
struct nested_record { struct inner_record inner; uint32_t tail; };
struct long_record { long number; };
#define DECLARE(T) extern struct T wa_pass_##T(struct T);
DECLARE(byte_record) DECLARE(short_record) DECLARE(tiny_record) DECLARE(word_record)
DECLARE(pair_record) DECLARE(padded_record) DECLARE(pointer_record)
DECLARE(inner_record) DECLARE(nested_record) DECLARE(long_record)
struct byte_record wa_bump_byte_record(struct byte_record x) { x.byte += 13; return x; }
struct short_record wa_bump_short_record(struct short_record x) { x.low = -19; x.high += 17; return x; }
struct tiny_record wa_bump_tiny_record(struct tiny_record x) { x.count += 42; return x; }
struct word_record wa_bump_word_record(struct word_record x) { x.bits ^= UINT64_C(0x8123456789abcdef); return x; }
struct pair_record wa_bump_pair_record(struct pair_record x) { x.first += 9; x.second ^= UINT32_C(0xc2345678); return x; }
struct padded_record wa_bump_padded_record(struct padded_record x) { x.tag ^= 0x80; x.payload += 19; return x; }
struct pointer_record wa_bump_pointer_record(struct pointer_record x) { return x; }
struct inner_record wa_bump_inner_record(struct inner_record x) { x.first += 7; x.second += 11; return x; }
struct nested_record wa_bump_nested_record(struct nested_record x) { x.inner.first += 13; x.inner.second += 17; x.tail += 19; return x; }
struct long_record wa_bump_long_record(struct long_record x) { x.number -= 17; return x; }
static unsigned truth_calls;
struct pair_record wa_next_pair(void) { ++truth_calls; return (struct pair_record){0,0}; }
extern uint64_t wa_pair_truth(void);
extern struct pair_record wa_choose_pair(int, struct pair_record, struct pair_record);
extern struct pair_record wa_stack(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,struct pair_record);
struct pair_record wa_stack_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,uint64_t h,struct pair_record x) {
 assert(a==1 && b==2 && c==3 && d==4 && e==5 && f==6 && g==7 && h==8);
 x.first+=36; x.second^=UINT32_MAX; return x;
}
extern struct padded_record wa_mixed(double,struct tiny_record,double,struct padded_record,uint64_t);
struct padded_record wa_mixed_c(double a,struct tiny_record b,double c,struct padded_record d,uint64_t e) {
 assert(a==1.25 && c==-3.5 && e==37 && b.count==UINT32_C(0xfedcba98));
 d.tag += 3; d.payload ^= b.count; return d;
}
int main(void) {
 struct byte_record b={250}; b=wa_pass_byte_record(b); assert(b.byte==7);
 struct short_record s={-128,244}; s=wa_pass_short_record(s); assert(s.low==-19 && s.high==5);
 struct tiny_record t={UINT32_MAX-10}; t=wa_pass_tiny_record(t); assert(t.count==31);
 struct word_record w={UINT64_C(0xfedcba9876543210)}; uint64_t old=w.bits; w=wa_pass_word_record(w); assert(w.bits==(old^UINT64_C(0x8123456789abcdef)));
 struct pair_record p={UINT32_MAX-4,UINT32_C(0xdeadbeef)}; p=wa_pass_pair_record(p); assert(p.first==4 && p.second==(UINT32_C(0xdeadbeef)^UINT32_C(0xc2345678)));
 struct padded_record d={0x91,UINT32_MAX-7}; d=wa_pass_padded_record(d); assert(d.tag==0x11 && d.payload==11);
 int marker=7; struct pointer_record q={&marker}; assert(wa_pass_pointer_record(q).address==&marker);
 struct inner_record i={65532,65530}; i=wa_pass_inner_record(i); assert(i.first==3 && i.second==5);
 struct nested_record n={{65530,65525},UINT32_MAX-7}; n=wa_pass_nested_record(n); assert(n.inner.first==7 && n.inner.second==6 && n.tail==11);
 struct long_record l={-700}; assert(wa_pass_long_record(l).number==-717);
 struct pair_record x={12,UINT32_C(0x80000001)},y={42,99}; p=wa_choose_pair(0,x,y); assert(p.first==12 && p.second==UINT32_C(0x80000001)); p=wa_choose_pair(1,x,y); assert(p.first==42 && p.second==99);
 assert(wa_pair_truth()==42 && truth_calls==1);
 p=wa_stack(1,2,3,4,5,6,7,8,x); assert(p.first==48 && p.second==UINT32_C(0x7ffffffe));
 d=wa_mixed(1.25,(struct tiny_record){UINT32_C(0xfedcba98)},-3.5,(struct padded_record){250,17},37); assert(d.tag==253 && d.payload==(17^UINT32_C(0xfedcba98)));
 struct nested_record dest={{1,65530},UINT32_C(0x12345678)};
 extern uint16_t wa_nested_second(const struct nested_record *);
 assert(wa_nested_second(&dest)==65530 && dest.tail==UINT32_C(0x12345678));
 extern uint32_t wa_padded_payload(struct padded_record *,uint32_t);
 struct padded_record field={91,0}; assert(wa_padded_payload(&field,UINT32_C(0x80000001))==UINT32_C(0x80000001)); assert(field.tag==91 && field.payload==UINT32_C(0x80000001));
 puts("native word aggregate C ABI, branch, scalar fields and truth checks passed");
}
