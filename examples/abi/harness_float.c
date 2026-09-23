extern double pass_mix(long, double, float, long);
extern double pass_nine_floats(double, double, double, double, double,
                               double, double, double, double);
extern float float_constant(void);
extern double double_constant(void);

double mix_c(long a, double b, float c, long d)
{
    return a + b + c + d;
}

double sum9_c(double a, double b, double c, double d, double e,
              double f, double g, double h, double i)
{
    return a + b + c + d + e + f + g + h + i;
}

int main(void)
{
    if (pass_mix(2, 3.5, 1.25f, 4) != 10.75)
        return 1;
    if (pass_nine_floats(1, 2, 3, 4, 5, 6, 7, 8, 9) != 45)
        return 2;
    if (float_constant() != 1.25f || double_constant() != 3.5)
        return 3;
    return 0;
}
