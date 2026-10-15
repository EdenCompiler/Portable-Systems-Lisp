#include <stdint.h>

struct word_record {
    uint64_t bits;
};

struct word_record next_word_c(struct word_record value)
{
    value.bits += 1;
    return value;
}

extern struct word_record roundtrip_word_record(struct word_record value);

int main(void)
{
    struct word_record result = roundtrip_word_record((struct word_record){41});
    return result.bits == 42 ? 0 : 1;
}
