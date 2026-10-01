#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static uint32_t fb(float x) { uint32_t y;memcpy(&y,&x,4);return y; }
static uint64_t db(double x) { uint64_t y;memcpy(&y,&x,8);return y; }
static float fv(uint32_t x) { float y;memcpy(&y,&x,4);return y; }
static double dv(uint64_t x) { double y;memcpy(&y,&x,8);return y; }
static const uint32_t singles[]={0x80000000u,0x7fc00421u,1u,0x3f800000u,0x7f800000u,0x7f800001u};
static const uint64_t doubles[]={0x7ff8000000000421ull,0x8000000000000000ull,1ull,0x3ff0000000000000ull,0x7ff0000000000000ull,0x7ff0000000000001ull};
extern double forward_abi(float, double, float, double, float, double, float, double, float, double, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
extern float first_single(float, double, float, double, float, double, float, double, float, double, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
double check_large(float s0, double d0, float s1, double d1, float s2, double d2, float s3, double d3, float s4, double d4, uint64_t i0, uint64_t i1, uint64_t i2, uint64_t i3, uint64_t i4, uint64_t i5, uint64_t i6, uint64_t i7, uint64_t i8) {
    assert(fb(s0)==singles[0]);
    assert(db(d0)==doubles[0]);
    assert(fb(s1)==singles[1]);
    assert(db(d1)==doubles[1]);
    assert(fb(s2)==singles[2]);
    assert(db(d2)==doubles[2]);
    assert(fb(s3)==singles[3]);
    assert(db(d3)==doubles[3]);
    assert(fb(s4)==singles[4]);
    assert(db(d4)==doubles[4]);
    assert(i0==UINT64_C(9305357564029960192));
    assert(i1==UINT64_C(9305357564029960193));
    assert(i2==UINT64_C(9305357564029960194));
    assert(i3==UINT64_C(9305357564029960195));
    assert(i4==UINT64_C(9305357564029960196));
    assert(i5==UINT64_C(9305357564029960197));
    assert(i6==UINT64_C(9305357564029960198));
    assert(i7==UINT64_C(9305357564029960199));
    assert(i8==UINT64_C(9305357564029960200));
    return d0;
}
float echo_single(float x) { return x; }
double echo_double(double x) { return x; }
static int calls;
float next_single(int id) { assert(++calls==id);return id==1?1.25f:6.0f; }
double ordered_pair(float a, float b) { assert(calls==2);return a+b; }
extern float single_roundtrip(float);
extern double double_roundtrip(double);
extern double recursive_float(double,uint64_t);
extern double ordered_float(void);
extern float choose_single(float,float,uint64_t);
int main(void) {
    assert(db(forward_abi(fv(singles[0]), dv(doubles[0]), fv(singles[1]), dv(doubles[1]), fv(singles[2]), dv(doubles[2]), fv(singles[3]), dv(doubles[3]), fv(singles[4]), dv(doubles[4]), UINT64_C(9305357564029960192), UINT64_C(9305357564029960193), UINT64_C(9305357564029960194), UINT64_C(9305357564029960195), UINT64_C(9305357564029960196), UINT64_C(9305357564029960197), UINT64_C(9305357564029960198), UINT64_C(9305357564029960199), UINT64_C(9305357564029960200)))==doubles[0]);
    assert(fb(first_single(fv(singles[0]), dv(doubles[0]), fv(singles[1]), dv(doubles[1]), fv(singles[2]), dv(doubles[2]), fv(singles[3]), dv(doubles[3]), fv(singles[4]), dv(doubles[4]), UINT64_C(9305357564029960192), UINT64_C(9305357564029960193), UINT64_C(9305357564029960194), UINT64_C(9305357564029960195), UINT64_C(9305357564029960196), UINT64_C(9305357564029960197), UINT64_C(9305357564029960198), UINT64_C(9305357564029960199), UINT64_C(9305357564029960200)))==singles[0]);
    const unsigned count=sizeof singles/sizeof singles[0];
    for(unsigned i=0;i<count;i++) {
        assert(fb(single_roundtrip(fv(singles[i])))==singles[i]);
        assert(fb(choose_single(fv(singles[i]),fv(singles[count-1-i]),1))==singles[i]);
        assert(fb(choose_single(fv(singles[i]),fv(singles[count-1-i]),0))==singles[count-1-i]);
        assert(db(double_roundtrip(dv(doubles[i])))==doubles[i]);
        assert(db(recursive_float(dv(doubles[i]),31))==doubles[i]);
    }
    assert(ordered_float()==7.25);
    puts("mixed floating ABI registers, overflow, recursion and evaluation order passed");
}
