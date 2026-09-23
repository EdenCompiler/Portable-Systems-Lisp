extern long psl_counter;
extern long c_counter;
extern double psl_ratio;
extern double c_ratio;
extern unsigned char *psl_pointer;
extern unsigned char *c_pointer;
extern long read_psl_counter(void);
extern long increment_c_counter(void);
extern double read_psl_ratio(void);
extern double replace_c_ratio(void);
extern unsigned char read_pointed_byte(void);

int main(void)
{
    if (psl_counter != 41 || read_psl_counter() != 41)
        return 1;
    psl_counter = 73;
    if (read_psl_counter() != 73)
        return 2;
    if (increment_c_counter() != 11 || c_counter != 11)
        return 3;
    if (psl_ratio != 2.5 || read_psl_ratio() != 2.5)
        return 4;
    if (replace_c_ratio() != 3.5 || c_ratio != 3.5)
        return 5;
    if (psl_pointer != 0 || read_pointed_byte() != 77 || *c_pointer != 77)
        return 6;
    return 0;
}
