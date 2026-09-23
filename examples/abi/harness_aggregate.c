#include <stdint.h>

struct pair { uint64_t first; uint64_t second; };
struct tiny { uint32_t value; };
struct mixed { uint64_t id; double weight; };
struct mixed_reverse { double weight; uint64_t id; };
struct two_floats { double first; double second; };
struct combined { float measure; int count; };

extern struct pair pass_pair(struct pair);
extern struct tiny pass_tiny(struct tiny);
extern struct pair roundtrip_exhausted(uint64_t, uint64_t, uint64_t,
                                       uint64_t, uint64_t, struct pair);
extern struct mixed pass_mixed(struct mixed);
extern struct mixed_reverse pass_mixed_reverse(struct mixed_reverse);
extern struct two_floats pass_two_floats(struct two_floats);
extern struct combined pass_combined(struct combined);
extern struct mixed roundtrip_exhausted_mixed(double, double, double, double,
                                              double, double, double, double,
                                              struct mixed);

struct pair bump_pair_c(struct pair value)
{
    value.first += 3;
    value.second += 5;
    return value;
}

struct tiny bump_tiny_c(struct tiny value)
{
    value.value += 7;
    return value;
}

struct pair exhausted_pair_c(uint64_t a, uint64_t b, uint64_t c,
                             uint64_t d, uint64_t e, struct pair value)
{
    value.first += a + b + c + d + e;
    value.second += 1;
    return value;
}

struct mixed bump_mixed_c(struct mixed value)
{
    value.id += 2;
    value.weight += 0.5;
    return value;
}

struct mixed_reverse bump_mixed_reverse_c(struct mixed_reverse value)
{
    value.id += 3;
    value.weight += 1.5;
    return value;
}

struct two_floats bump_two_floats_c(struct two_floats value)
{
    value.first += 1.0;
    value.second += 2.0;
    return value;
}

struct combined bump_combined_c(struct combined value)
{
    value.measure += 0.5f;
    value.count += 4;
    return value;
}

struct mixed exhausted_mixed_c(double a, double b, double c, double d,
                               double e, double f, double g, double h,
                               struct mixed value)
{
    value.id += 1;
    value.weight += a + b + c + d + e + f + g + h;
    return value;
}

int main(void)
{
    struct pair pair = pass_pair((struct pair){ 11, 13 });
    struct tiny tiny = pass_tiny((struct tiny){ 17 });
    struct pair exhausted = roundtrip_exhausted(1, 2, 3, 4, 5,
                                                (struct pair){ 19, 23 });
    struct mixed mixed = pass_mixed((struct mixed){ 9, 2.0 });
    struct mixed_reverse reverse =
        pass_mixed_reverse((struct mixed_reverse){ 3.0, 11 });
    struct two_floats floats =
        pass_two_floats((struct two_floats){ 4.0, 5.0 });
    struct combined combined =
        pass_combined((struct combined){ 1.0f, 6 });
    struct mixed exhausted_mixed =
        roundtrip_exhausted_mixed(1, 2, 3, 4, 5, 6, 7, 8,
                                  (struct mixed){ 12, 1.0 });
    if (pair.first != 14 || pair.second != 18)
        return 1;
    if (tiny.value != 24)
        return 2;
    if (exhausted.first != 34 || exhausted.second != 24)
        return 3;
    if (mixed.id != 11 || mixed.weight != 2.5)
        return 4;
    if (reverse.id != 14 || reverse.weight != 4.5)
        return 5;
    if (floats.first != 5.0 || floats.second != 7.0)
        return 6;
    if (combined.measure != 1.5f || combined.count != 10)
        return 8;
    if (exhausted_mixed.id != 13 || exhausted_mixed.weight != 37.0)
        return 7;
    return 0;
}
