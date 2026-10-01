#include <assert.h>
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../bootstrap/native_api.h"
static void check_reference(const char *text, int code, const char *reference) {
    uint32_t numerator[129] = {[128]=UINT32_C(0xa5a51234)};
    uint32_t denominator[129] = {[128]=UINT32_C(0x5a5a4321)};
    struct native_float_parser state;
    struct psl_parsed_integer out = {0};
    size_t n = strlen(text);
    size_t reference_length=strlen(reference);
    char *normalized=malloc(reference_length+1);
    assert(normalized);
    memcpy(normalized, reference, reference_length+1);
    for (size_t i=0; i<reference_length; i++) {
        if (normalized[i]=='d' || normalized[i]=='D' || normalized[i]=='l' ||
            normalized[i]=='L' || normalized[i]=='f' || normalized[i]=='F' ||
            normalized[i]=='s' || normalized[i]=='S') normalized[i]='e';
    }
    uint64_t expected=0;
    int overflow=0;
    if (code==13) {
        float value=strtof(normalized, NULL);
        uint32_t bits; memcpy(&bits, &value, sizeof bits); expected=bits;
        overflow=isinf(value);
    } else {
        double value=strtod(normalized, NULL);
        memcpy(&expected, &value, sizeof expected); overflow=isinf(value);
    }
    free(normalized);
    int result=parse_float_token((const uint8_t *)text, 0, n, &state,
                                numerator, denominator, 128, &out);
    assert(numerator[128]==UINT32_C(0xa5a51234));
    assert(denominator[128]==UINT32_C(0x5a5a4321));
    if ((overflow && result!=2) || (!overflow &&
        (result!=1 || out.radix!=code || out.magnitude!=expected))) {
        fprintf(stderr, "%.100s (length=%zu): code=%d result=%d got=%016" PRIx64
                " expected=%016" PRIx64 "\n", text, n, code, result,
                out.magnitude, expected);
        abort();
    }
}
static void check(const char *text, int code) {
    check_reference(text,code,text);
}
int main(void) {
    const char *single[]={"0.0", "-0.0", "1e0", ".5", "+1.25f0", "1.f0",
        "3.4028234663852886e38", "3.4028235677973366e38", "1e39",
        "1.1754943508222875e-38", "1.401298464324817e-45",
        "7.006492321624085354618647916449580656401e-46",
        "1.000000059604644775390625f0", "1.000000178813934326171875f0",
        "1e-9999", "-1e-9999", "1e9999"};
    const char *wide[]={"0d0", "-0d0", "1.d0", "1.0d-9999", "1.0d9999",
        "1.7976931348623157d308", "1.7976931348623159d308",
        "2.2250738585072014d-308", "4.9406564584124654d-324",
        "2.4703282292062327d-324", "2.4703282292062328d-324",
        "1.00000000000000011102230246251565404236316680908203125d0",
        "1.00000000000000033306690738754696212708950042724609375d0"};
    for (size_t i=0; i<sizeof single/sizeof single[0]; i++) check(single[i],13);
    for (size_t i=0; i<sizeof wide/sizeof wide[0]; i++) check(wide[i],14);
    uint32_t random=0x3821231u;
    char text[4096];
    for (unsigned i=0;i<600;i++) {
        random=random*1664525u+1013904223u;
        unsigned digits=1+random%950;
        text[0]='0'; text[1]='.';
        for (unsigned j=0;j<digits;j++) {
            random=random*1664525u+1013904223u;
            text[j+2]=(char)('0'+random%10);
        }
        int exponent=(int)(random%700)-350;
        snprintf(text+digits+2,sizeof(text)-digits-2,"d%d",exponent);
        check(text,14);
        snprintf(text+digits+2,sizeof(text)-digits-2,"e%d",exponent);
        check(text,13);
    }
    /* A distant nonzero tail distinguishes above-halfway from an exact tie. */
    const char *half="1.00000000000000011102230246251565404236316680908203125";
    size_t half_length=strlen(half);
    memcpy(text,half,half_length);
    memset(text+half_length,'0',900);
    strcpy(text+half_length+900,"1d0");
    check(text,14);
    /* The exponent cancels millions of fractional zeros, without recursion. */
    size_t zeros=2100000;
    char *long_text=malloc(zeros+32);
    assert(long_text);
    memcpy(long_text,"0.",2);
    memset(long_text+2,'0',zeros);
    snprintf(long_text+zeros+2,30,"1d%zu",zeros+1);
    /* Some C libraries clamp large exponents before cancelling the mantissa.
       Compare this exact value against the equivalent short C spelling. */
    check_reference(long_text,14,"1.0e0");
    free(long_text);
    const char *invalid[]={"1d", "1dd0", "1.2.3", ".", "1f+", "foo", "1", "1."};
    for(unsigned i=0;i<sizeof invalid/sizeof invalid[0];i++) {
        uint32_t numerator[128], denominator[128];
        struct native_float_parser state;
        struct psl_parsed_integer out={UINT64_C(0x42214221),0,0};
        assert(parse_float_token((const uint8_t *)invalid[i],0,strlen(invalid[i]),
                                  &state,numerator,denominator,128,&out)==0);
        assert(out.magnitude==UINT64_C(0x42214221));
    }
    struct native_float_parser state;
    struct psl_parsed_integer out={0};
    uint32_t numerator[128]={0}, denominator[128]={0};
    assert(parse_float_token((const uint8_t *)"1.0",0,3,&state,numerator,
                            denominator,127,&out)==2);
    assert(parse_float_token((const uint8_t *)"1.0",UINTPTR_MAX,3,&state,
                            numerator,denominator,128,&out)==2);
    puts("native decimal IEEE payloads match independent C conversion");
}
