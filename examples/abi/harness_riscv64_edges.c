#include <stdint.h>

struct pair { uint64_t first, second; };

extern struct pair split_pair(uint64_t, uint64_t, uint64_t, uint64_t,
                              uint64_t, uint64_t, uint64_t, struct pair);
extern uint64_t sum9(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t,
                     uint64_t, uint64_t, uint64_t, uint64_t);
extern int64_t signed9(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t,
                       uint64_t, uint64_t, uint64_t, int8_t);
extern double float9(double, double, double, double, double,
                     double, double, double, double);

struct pair split_pair_c(uint64_t a, uint64_t b, uint64_t c, uint64_t d,
                         uint64_t e, uint64_t f, uint64_t g,
                         struct pair value)
{
    value.first += a + b + c + d + e + f + g;
    value.second += 1;
    return value;
}

uint64_t sum9_c(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e,
                uint64_t f, uint64_t g, uint64_t h, uint64_t i)
{
    return a + b + c + d + e + f + g + h + i;
}

int64_t signed9_c(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e,
                  uint64_t f, uint64_t g, uint64_t h, int8_t i)
{
    return a + b + c + d + e + f + g + h + i;
}

double float9_c(double a, double b, double c, double d, double e,
                double f, double g, double h, double i)
{
    return a + b + c + d + e + f + g + h + i;
}

int main(void)
{
    struct pair pair = split_pair(1, 2, 3, 4, 5, 6, 7,
                                  (struct pair){11, 13});
    if (pair.first != 39 || pair.second != 14)
        return 1;
    if (sum9(1, 2, 3, 4, 5, 6, 7, 8, 9) != 45)
        return 2;
    if (signed9(1, 2, 3, 4, 5, 6, 7, 8, -7) != 29)
        return 3;
    if (float9(1, 2, 3, 4, 5, 6, 7, 8, 9) != 45.0)
        return 4;
    return 0;
}
