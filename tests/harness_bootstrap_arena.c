#include <stdint.h>
#include <stddef.h>

struct psl_arena {
    uint8_t *data;
    uintptr_t used;
    uintptr_t capacity;
};

extern uint8_t *arena_alloc(struct psl_arena *arena, uintptr_t size,
                            uintptr_t alignment);

int main(void) {
    _Alignas(16) uint8_t bytes[32] = {0};
    struct psl_arena arena = {bytes, 0, sizeof bytes};
    uint8_t *first = arena_alloc(&arena, 3, 1);
    uint8_t *second = arena_alloc(&arena, 8, 8);

    if (first != bytes || second != bytes + 8 || arena.used != 16) return 1;
    if (arena_alloc(&arena, 1, 3) != NULL || arena.used != 16) return 2;
    if (arena_alloc(&arena, 17, 8) != NULL || arena.used != 16) return 3;
    if (arena_alloc(&arena, 16, 16) != bytes + 16) return 4;
    if (arena.used != 32) return 5;
    if (arena_alloc(&arena, 1, 1) != NULL || arena.used != 32) return 6;
    return 0;
}
