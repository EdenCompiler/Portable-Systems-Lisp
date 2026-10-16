#include "../runtime/psl_runtime.h"
psl_value native_cli_source_value(void) {
    return psl_rt_cons_precise(psl_rt_fixnum(42), PSL_NIL);
}
