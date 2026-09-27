#include <stddef.h>
#include <stdint.h>

struct query_inner { uint8_t byte; uint32_t word; };
struct query_outer { uint8_t tag; struct query_inner inner; void *memory; };
extern size_t query_inner_size(void), query_outer_size(void);
extern size_t query_outer_alignment(void), query_inner_offset(void), query_memory_offset(void);
extern size_t query_pointer_size(void), query_scalar_size(void);
extern uintptr_t pointer_address(const uint8_t *), opaque_address(void *);
extern uintptr_t address_roundtrip(uintptr_t);
extern uint64_t pointer_check(void *);

int main(void) {
    uint8_t byte = 1;
    if (query_inner_size() != sizeof(struct query_inner)) return 1;
    if (query_outer_size() != sizeof(struct query_outer)) return 2;
    if (query_outer_alignment() != _Alignof(struct query_outer)) return 3;
    if (query_inner_offset() != offsetof(struct query_outer, inner)) return 4;
    if (query_memory_offset() != offsetof(struct query_outer, memory)) return 5;
    if (query_pointer_size() != sizeof(void *) || query_scalar_size() != sizeof(uint16_t)) return 6;
    if (pointer_address(&byte) != (uintptr_t)&byte || opaque_address(&byte) != (uintptr_t)&byte) return 8;
    if (pointer_address(0) || opaque_address(0)) return 9;
    const uintptr_t addresses[] = {0, 1, UINTPTR_MAX, UINT64_C(0x8000000000000000)};
    for (size_t i = 0; i < sizeof addresses / sizeof addresses[0]; ++i)
        if (address_roundtrip(addresses[i]) != addresses[i]) return 10;
    if (pointer_check(0) != 42 || pointer_check(&byte) != 43) return 11;
    return 0;
}
