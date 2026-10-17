#include "../runtime/psl_runtime.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "stale") == 0) {
        size_t stale = psl_rt_value_handle_open();
        psl_rt_value_handle_close(stale);
        (void)psl_rt_value_handle_get(stale);
        return 0;
    }
    size_t first = psl_rt_value_handle_open();
    size_t second = psl_rt_value_handle_open();
    assert(first != 0 && second != 0 && first != second);
    assert(psl_rt_live_value_handles() == 2);
    assert(psl_rt_value_handle_get(first) == PSL_NIL);
    assert(psl_rt_value_handle_get(second) == PSL_NIL);

    psl_value string = psl_rt_make_string_precise(5, (uint8_t)'m');
    psl_value pair = psl_rt_cons_precise(psl_rt_fixnum(41), string);
    psl_rt_value_handle_set(first, pair);
    psl_rt_collect_precise();
    pair = psl_rt_value_handle_get(first);
    assert(psl_rt_unbox_fixnum(psl_rt_car(pair)) == 41);
    string = psl_rt_cdr(pair);
    assert(psl_rt_string_length(string) == 5);
    assert(psl_rt_string_byte(string, 4) == (uint8_t)'m');

    psl_rt_value_handle_set(second, psl_rt_fixnum(99));
    psl_rt_value_handle_close(first);
    assert(psl_rt_unbox_fixnum(psl_rt_value_handle_get(second)) == 99);
    psl_rt_value_handle_close(second);
    assert(psl_rt_live_value_handles() == 0);
    psl_rt_collect_precise();
    assert(psl_rt_live_objects() == 0);
    for (size_t index = 0; index < 128; index++) {
        size_t token = psl_rt_value_handle_open();
        psl_rt_value_handle_close(token);
    }
    assert(psl_rt_live_value_handles() == 0);
    puts("opaque value handles root managed graphs, support independent close order, and release roots");
    return 0;
}
