extern long psl_counter;
extern long c_counter;
extern long read_psl_counter(void);
extern long increment_c_counter(void);

long c_counter = 10;

int main(void)
{
    if (psl_counter != 41 || read_psl_counter() != 41)
        return 1;
    psl_counter = 73;
    if (read_psl_counter() != 73)
        return 2;
    if (increment_c_counter() != 11 || c_counter != 11)
        return 3;
    return 0;
}
