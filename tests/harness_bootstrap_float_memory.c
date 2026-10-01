#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
struct float_record { float single; double wide; };
extern float psl_single;
extern double psl_wide, psl_small;
extern int float_copy(float *, const float *);
extern int double_copy(double *, const double *);
extern int float_store(float *);
extern int double_store(double *);
extern int float_field_store(struct float_record *);
extern int float_truth(const float *);
extern int float_literal_truth(void);
extern int float_branch_copy(double *, const double *, const double *, uint64_t);
static uint32_t single_bits(const float *p) { uint32_t v; memcpy(&v,p,4); return v; }
static uint64_t wide_bits(const double *p) { uint64_t v; memcpy(&v,p,8); return v; }
int main(void) {
    assert(single_bits(&psl_single)==UINT32_C(0x80000000));
    assert(wide_bits(&psl_wide)==UINT64_C(0x3ff0000000000002));
    assert(wide_bits(&psl_small)==1);
    uint32_t singles[]={0, UINT32_C(0x80000000), UINT32_C(0x7fc00421), UINT32_C(0x7f800001)};
    uint64_t wides[]={0, UINT64_C(0x8000000000000000), UINT64_C(0x7ff8000000000421), UINT64_C(0x7ff0000000000001)};
    for(unsigned i=0;i<4;i++) {
        float source, destination=1.0f; memcpy(&source,&singles[i],4);
        assert(float_copy(&destination,&source)==0);
        assert(single_bits(&destination)==singles[i]);
        assert(float_truth(&source)==42);
        double from, to=1.0; memcpy(&from,&wides[i],8);
        assert(double_copy(&to,&from)==0);
        assert(wide_bits(&to)==wides[i]);
    }
    float single=0; double wide=1;
    assert(float_store(&single)==0 && single_bits(&single)==UINT32_C(0x3f800000));
    assert(double_store(&wide)==0 && wide_bits(&wide)==UINT64_C(0x8000000000000000));
    struct float_record record={0};
    assert(float_field_store(&record)==0 && record.single==0.5f && record.wide==3.25);
    assert(float_literal_truth()==42);
    double yes=17.25, no=-3.5;
    assert(float_branch_copy(&wide,&yes,&no,1)==0 && wide==yes);
    assert(float_branch_copy(&wide,&yes,&no,0)==0 && wide==no);
    puts("native floating literals, data, fields, payload copies and Lisp truth passed");
}
