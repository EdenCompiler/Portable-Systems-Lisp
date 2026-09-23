#include <stdint.h>

struct triple { uint32_t first, second, third; };

extern struct triple roundtrip_triple(struct triple value);
extern struct triple roundtrip_triple_stack(uint64_t a, uint64_t b,
                                           uint64_t c, uint64_t d,
                                           struct triple value);

struct triple bump_triple_c(struct triple value) {
    value.first += 1;
    value.second += 2;
    value.third += 3;
    return value;
}

struct triple bump_triple_stack_c(uint64_t a, uint64_t b, uint64_t c,
                                   uint64_t d, struct triple value) {
    value.first += (uint32_t)(a + b + c + d);
    value.third += 5;
    return value;
}

int main(void) {
    struct triple first = roundtrip_triple((struct triple){ 10, 20, 30 });
    struct triple second = roundtrip_triple_stack(
        1, 2, 3, 4, (struct triple){ 10, 20, 30 });
    if (sizeof(struct triple) != 12)
        return 1;
    if (first.first != 11 || first.second != 22 || first.third != 33)
        return 2;
    if (second.first != 20 || second.second != 20 || second.third != 35)
        return 3;
    return 0;
}
