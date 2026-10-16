#include "../runtime/psl_runtime.h"
psl_value native_cli_archive_value(void) {
    return psl_rt_cons(psl_rt_fixnum(42), PSL_NIL);
}
