#include "../runtime/psl_runtime.h"
extern psl_value native_cli_cons(void);
int main(void) {
    psl_value pair = native_cli_cons();
    return psl_rt_unbox_fixnum(psl_rt_car(pair)) == 42 ? 0 : 1;
}
