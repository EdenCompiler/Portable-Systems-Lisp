#include <assert.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>

struct alias_layout {
    signed char byte;
    unsigned short short_value;
    int integer;
    long long_value;
    size_t size;
    ptrdiff_t difference;
    unsigned long long wide;
    float single;
    double double_value;
};

extern int64_t alias_signed(signed char, short, int, long, long long, ptrdiff_t);
extern uint64_t alias_unsigned(unsigned char, unsigned short, unsigned int,
                               unsigned long, unsigned long long, size_t);
extern long alias_call(long);
extern long alias_memory(long *, long);
extern uintptr_t alias_long_size(void), alias_layout_size(void);
extern uintptr_t alias_layout_alignment(void), alias_long_offset(void), alias_double_offset(void);
extern unsigned long alias_export;

long alias_c_long(long value) { return value + 17; }

int main(void) {
    assert(alias_signed(-128, -32768, INT_MIN, -19L, -23LL, -29) ==
           INT64_C(-128) - 32768 + INT_MIN - 19 - 23 - 29);
    assert(alias_unsigned(UCHAR_MAX, USHRT_MAX, UINT_MAX, ULONG_MAX, 31ULL, 37) ==
           (uint64_t)UCHAR_MAX + USHRT_MAX + UINT_MAX + (uint64_t)ULONG_MAX + 31 + 37);
    assert(alias_call(-12345L) == -12328L);
    long memory = 0;
    assert(alias_memory(&memory, LONG_MIN) == LONG_MIN && memory == LONG_MIN);
    assert(alias_long_size() == sizeof(long));
    assert(alias_layout_size() == sizeof(struct alias_layout));
    assert(alias_layout_alignment() == _Alignof(struct alias_layout));
    assert(alias_long_offset() == offsetof(struct alias_layout, long_value));
    assert(alias_double_offset() == offsetof(struct alias_layout, double_value));
    assert(alias_export == 42UL);
    return 0;
}
