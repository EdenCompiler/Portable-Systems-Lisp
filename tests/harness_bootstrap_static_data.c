#include <stdint.h>
#include <string.h>

extern const unsigned char psl_message[];
extern const uint64_t psl_aligned_word;

int main(void) {
    if (strcmp((const char *)psl_message, "Portable Systems Lisp") != 0)
        return 1;
    if (psl_aligned_word != UINT64_C(0x1122334455667788))
        return 2;
    return (uintptr_t)&psl_aligned_word % 16 != 0;
}
