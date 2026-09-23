#include <stdint.h>

struct four_floats { float first, second, third, fourth; };
struct float_pair { float first, second; };
struct nested_floats { struct float_pair first, second; };

extern struct four_floats pass_four(struct four_floats);
extern struct nested_floats pass_nested(struct nested_floats);
extern struct four_floats pass_exhausted_four(
    float, float, float, float, float, float, float, float,
    struct four_floats);

struct four_floats bump_four_c(struct four_floats value)
{
    value.first += 1.0f;
    value.second += 2.0f;
    value.third += 3.0f;
    value.fourth += 4.0f;
    return value;
}

struct nested_floats bump_nested_c(struct nested_floats value)
{
    value.first.first += 1.0f;
    value.first.second += 2.0f;
    value.second.first += 3.0f;
    value.second.second += 4.0f;
    return value;
}

struct four_floats exhausted_four_c(
    float a, float b, float c, float d, float e, float f, float g, float h,
    struct four_floats value)
{
    value.first += a + b + c + d;
    value.second += e + f + g + h;
    return value;
}

int main(void)
{
    struct four_floats four = pass_four((struct four_floats){1, 2, 3, 4});
    struct nested_floats nested =
        pass_nested((struct nested_floats){{1, 2}, {3, 4}});
    struct four_floats exhausted = pass_exhausted_four(
        1, 2, 3, 4, 5, 6, 7, 8,
        (struct four_floats){10, 20, 30, 40});
    if (four.first != 2 || four.second != 4 ||
        four.third != 6 || four.fourth != 8)
        return 1;
    if (nested.first.first != 2 || nested.first.second != 4 ||
        nested.second.first != 6 || nested.second.second != 8)
        return 2;
    if (exhausted.first != 20 || exhausted.second != 46 ||
        exhausted.third != 30 || exhausted.fourth != 40)
        return 3;
    return 0;
}
