#include <assert.h>
#include <limits.h>
#include <stdint.h>

extern uint8_t only_byte;
extern uint16_t only_short;
extern int32_t only_signed;
extern uint64_t only_word;
extern uint8_t *only_pointer;

int main(void) {
    assert(only_byte == UINT8_MAX && only_short == UINT16_MAX);
    assert(only_signed == INT32_MIN && only_word == UINT64_MAX);
    assert(only_pointer == 0);
    assert((uintptr_t)&only_short % _Alignof(uint16_t) == 0);
    assert((uintptr_t)&only_signed % _Alignof(int32_t) == 0);
    assert((uintptr_t)&only_word % _Alignof(uint64_t) == 0);
    assert((uintptr_t)&only_pointer % _Alignof(void *) == 0);
    only_signed = 17;
    only_pointer = &only_byte;
    assert(*only_pointer == 255 && only_signed == 17);
    return 0;
}
