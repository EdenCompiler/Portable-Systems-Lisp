#include <stdint.h>
#include <stddef.h>

struct qualified_cell { uint16_t value; const volatile uint8_t *next; };
struct qualified_outer { struct qualified_cell cell; };
extern uint8_t qualifier_read(const uint8_t *, intptr_t);
extern const volatile uint8_t *qualifier_chain(const volatile uint8_t *const *);
extern uint16_t qualifier_fields(const volatile struct qualified_outer *);
extern uint16_t qualifier_writes(volatile uint16_t *);
extern uint16_t qualifier_discarded_read(const volatile uint16_t *);
extern uint8_t qualifier_cast_store(const uint8_t *, uint8_t);
extern int qualifier_null(void);
extern const volatile uint8_t *qualifier_from_bits(uintptr_t);

static uint16_t observations[2];
static unsigned count;
void qualifier_observe(uint16_t value) {
    if (count < 2) observations[count] = value;
    ++count;
}
void qualifier_update(volatile uint16_t *pointer) { *pointer = 42; }

int main(void) {
    uint8_t bytes[] = {1, 2, 3};
    const volatile uint8_t *slot = bytes;
    struct qualified_outer outer = {{UINT16_C(40000), bytes + 2}};
    volatile uint16_t word = 7;
    if (qualifier_read(bytes, 2) != 3 || qualifier_read(bytes + 2, -2) != 1)
        return 1;
    if (qualifier_chain(&slot) != bytes || qualifier_fields(&outer) != 40003)
        return 2;
    if (qualifier_writes(&word) != 42 || word != 42 || count != 2 ||
        observations[0] != 7 || observations[1] != UINT16_MAX) return 3;
    word = 12;
    if (qualifier_discarded_read(&word) != 42 || word != 42) return 4;
    if (qualifier_cast_store(bytes + 1, 99) != 99 || bytes[1] != 99 ||
        bytes[0] != 1 || bytes[2] != 3) return 5;
    if (qualifier_null() != 1 || qualifier_from_bits((uintptr_t)bytes) != bytes)
        return 6;
    return 0;
}
