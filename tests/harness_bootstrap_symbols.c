#include <assert.h>
#include <stdint.h>
#include <stdio.h>

uint64_t answer(void);
uintptr_t mixed_box_size(void);
uintptr_t mixed_box_payload_offset(void);

int main(void) {
    assert(answer() == 42);
    assert(mixed_box_size() == 8);
    assert(mixed_box_payload_offset() == 0);
    puts("PSL folded symbol identity passed");
    return 0;
}
