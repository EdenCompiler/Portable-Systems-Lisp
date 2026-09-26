#include <stdint.h>

extern uint32_t scalar_type_bits(uint32_t code);
extern int scalar_word_valid_p(uint32_t code, uint64_t value);

int main(void) {
    const uint32_t widths[] = {64, 64, 8, 16, 32, 8, 16, 32, 64, 64};
    for (uint32_t code = 1; code <= 10; ++code) {
        if (scalar_type_bits(code) != widths[code - 1]) return 1;
    }
    return scalar_word_valid_p(3, UINT8_MAX)
        && !scalar_word_valid_p(3, UINT64_C(256))
        && scalar_word_valid_p(6, INT8_MAX)
        && !scalar_word_valid_p(6, UINT64_C(128))
        && scalar_word_valid_p(6, UINT64_MAX)
        && scalar_word_valid_p(6, UINT64_MAX - 127)
        && !scalar_word_valid_p(6, UINT64_MAX - 128)
        && scalar_word_valid_p(5, UINT32_MAX)
        && !scalar_word_valid_p(5, UINT64_C(4294967296))
        && scalar_word_valid_p(8, UINT64_MAX - INT32_MAX)
        && !scalar_word_valid_p(8, UINT64_MAX - INT32_MAX - 1)
        && scalar_word_valid_p(1, UINT64_MAX)
        && scalar_word_valid_p(9, UINT64_MAX)
        && !scalar_word_valid_p(0, 0)
        && !scalar_word_valid_p(11, 0) ? 0 : 1;
}
