#include <stdint.h>

struct opaque_holder { void *memory; };
extern uint64_t heap_roundtrip(void);
extern void void_forward(uint64_t *, uint64_t);
extern void void_branch(uint64_t *, uint64_t);
extern void void_loop(uint64_t *);
extern void void_binding(uint64_t *);
extern void *opaque_roundtrip(struct opaque_holder *, void *);
extern uint64_t opaque_truth(void *);
static uint64_t log_value;

void void_store_c(uint64_t *output, uint64_t value) {
    *output = value;
    log_value = log_value * 10 + value;
}
void void_seven_c(uint64_t *output, uint64_t a, uint64_t b, uint64_t c,
                   uint64_t d, uint64_t e, uint64_t f) {
    *output = a + 10*b + 100*c + 1000*d + 10000*e + 100000*f;
}
int main(void) {
    uint64_t output = 0;
    struct opaque_holder holder = {0};
    if (heap_roundtrip() != 42) return 1;
    void_forward(&output, 3);
    if (output != 42 || log_value != 3252) return 2;
    void_branch(&output, 0);
    if (output != 654321) return 3;
    void_branch(&output, 1);
    if (output != 99) return 4;
    log_value = 0;
    void_loop(&output);
    if (output != 42 || log_value != 1272) return 5;
    void_binding(&output);
    if (output != 42) return 6;
    if (opaque_roundtrip(&holder, &output) != &output || holder.memory != &output) return 7;
    if (opaque_roundtrip(&holder, 0) || holder.memory) return 8;
    if (opaque_truth(0) != 42 || opaque_truth(&output) != 42) return 9;
    return 0;
}
