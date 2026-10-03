#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern uint64_t macro_nested(uint64_t), macro_effects(uint64_t), macro_bindings(uint64_t);
extern uint64_t macro_before(uint64_t), macro_after(uint64_t), macro_truth(uint64_t), macro_imported(uint64_t);
static unsigned ticks;
uint64_t macro_tick(uint64_t value) { ++ticks; return value + ticks; }
int main(void) {
    const uint64_t values[] = {0, 1, 42, UINT64_MAX, UINT64_MAX / 2};
    for (unsigned i=0; i<sizeof values/sizeof values[0]; ++i) {
        uint64_t value=values[i];
        assert(macro_nested(value)==value*4);
        ticks=0;
        assert(macro_effects(value)==value*2+3 && ticks==2);
        assert(macro_bindings(value)==value*2+42);
        assert(macro_before(value)==value*2);
        assert(macro_after(value)==value+3);
        assert(macro_truth(value)==value);
        assert(macro_imported(value)==value+9);
    }
    puts("nested, ordered and imported build-host macros passed");
    return 0;
}
