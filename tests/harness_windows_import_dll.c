extern long c_counter;
extern long psl_counter;
extern long increment_c_counter(void);

int main(void) {
    return psl_counter == 41 && increment_c_counter() == 11 &&
           c_counter == 11 ? 0 : 1;
}
