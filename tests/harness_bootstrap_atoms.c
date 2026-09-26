#include <stdint.h>
#include <string.h>

struct psl_parsed_integer {
    uint64_t magnitude;
    uint8_t negative;
    uint8_t radix;
};

extern int parse_integer_token(const uint8_t *data, uintptr_t start,
                               uintptr_t length,
                               struct psl_parsed_integer *output);

static int check(const char *source, int status, uint64_t value,
                 uint8_t negative, uint8_t radix) {
    struct psl_parsed_integer output = {0};
    int actual = parse_integer_token((const uint8_t *)source, 0,
                                     strlen(source), &output);
    if (actual != status) return 1;
    if (status == 1 && (output.magnitude != value ||
                        output.negative != negative ||
                        output.radix != radix)) return 2;
    return 0;
}

int main(void) {
    if (check("0", 1, 0, 0, 10)) return 1;
    if (check("18446744073709551615", 1, UINT64_MAX, 0, 10)) return 2;
    if (check("18446744073709551616", 2, 0, 0, 0)) return 3;
    if (check("-9223372036854775808", 1,
              UINT64_C(9223372036854775808), 1, 10)) return 4;
    if (check("#xFF", 1, 255, 0, 16)) return 5;
    if (check("#b1011", 1, 11, 0, 2)) return 6;
    if (check("#o77", 1, 63, 0, 8)) return 7;
    if (check("+42", 1, 42, 0, 10)) return 8;
    if (check("name", 0, 0, 0, 0)) return 9;
    if (check("12abc", 0, 0, 0, 0)) return 10;
    if (check("#x", 0, 0, 0, 0)) return 11;
    if (check("#x10000000000000000", 2, 0, 0, 0)) return 12;
    return 0;
}
