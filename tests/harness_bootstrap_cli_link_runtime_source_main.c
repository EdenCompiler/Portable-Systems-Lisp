#include "../runtime/psl_runtime.h"
#include <stdint.h>
extern uint64_t native_cli_answer(void);
extern psl_value native_cli_source_value(void);
int main(void) {
    return psl_rt_unbox_fixnum(psl_rt_car(native_cli_source_value())) ==
                   (int64_t)native_cli_answer() ? 0 : 1;
}
