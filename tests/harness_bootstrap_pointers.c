#include <stdint.h>
#include <stddef.h>

struct memory_pair { uint8_t tag; int32_t value; uint16_t *data; };
struct memory_outer { uint64_t first; struct memory_pair pair; };
extern uint16_t *pointer_choose(uint16_t *);
extern uint16_t *pointer_offset(uint16_t *, intptr_t);
extern int64_t pointer_read8(const int8_t *);
extern int64_t pointer_read16(const int16_t *);
extern int64_t pointer_read32(const int32_t *);
extern int64_t pointer_read64(const int64_t *);
extern uint8_t pointer_write8(uint8_t *, uint8_t);
extern uint16_t pointer_write16(uint16_t *, uint16_t);
extern uint32_t pointer_write32(uint32_t *, uint32_t);
extern uint64_t pointer_write64(uint64_t *, uint64_t);
extern uint16_t *pointer_chain(uint16_t **, uint16_t *);
extern uint16_t pointer_nested(struct memory_outer *, int32_t, uint16_t *);
extern uint8_t pointer_cast_byte(uint16_t *);
extern int pointer_null_truth(void);
extern uint16_t *pointer_from_bits(uintptr_t);
extern uint32_t pointer_loop(uint32_t *, uint32_t);
extern uint32_t pointer_store_order(uint32_t *);

extern uint64_t pointer_unsigned8(const uint8_t *);
extern uint64_t pointer_unsigned16(const uint16_t *);
extern uint64_t pointer_unsigned32(const uint32_t *);
extern uint64_t pointer_unsigned64(const uint64_t *);
extern int32_t pointer_struct_stride(struct memory_pair *, intptr_t);

static int check_unsigned_loads(void) {
    const uint8_t a = UINT8_MAX;
    const uint16_t b = UINT16_MAX;
    const uint32_t c = UINT32_MAX;
    const uint64_t d = UINT64_MAX;
    return pointer_unsigned8(&a) == a && pointer_unsigned16(&b) == b &&
           pointer_unsigned32(&c) == c && pointer_unsigned64(&d) == d;
}

static int check_signed_loads(void) {
    int8_t a = INT8_MIN;
    int16_t b = INT16_MIN;
    int32_t c = INT32_MIN;
    int64_t d = INT64_MIN;
    return pointer_read8(&a) == a && pointer_read16(&b) == b &&
           pointer_read32(&c) == c && pointer_read64(&d) == d;
}

static int check_stores(void) {
    uint8_t a[3] = {1, 0, 2};
    uint16_t b[3] = {3, 0, 4};
    uint32_t c[3] = {5, 0, 6};
    uint64_t d[3] = {7, 0, 8};
    if (pointer_write8(&a[1], UINT8_MAX) != UINT8_MAX || a[1] != UINT8_MAX ||
        a[0] != 1 || a[2] != 2) return 0;
    if (pointer_write16(&b[1], UINT16_MAX) != UINT16_MAX || b[1] != UINT16_MAX ||
        b[0] != 3 || b[2] != 4) return 0;
    if (pointer_write32(&c[1], UINT32_MAX) != UINT32_MAX || c[1] != UINT32_MAX ||
        c[0] != 5 || c[2] != 6) return 0;
    return pointer_write64(&d[1], UINT64_MAX) == UINT64_MAX &&
           d[1] == UINT64_MAX && d[0] == 7 && d[2] == 8;
}

static int check_pointers(void) {
    uint16_t data[3] = {0x1234, 42, UINT16_MAX};
    uint16_t *slot = NULL;
    struct memory_pair pairs[2] = {{1, -12, NULL}, {2, 42, NULL}};
    struct memory_outer outer = {123, {7, 0, NULL}};
    if (pointer_choose(data) != data || pointer_offset(data, 2) != data + 2 ||
        pointer_offset(data + 2, -2) != data) return 0;
    if (pointer_chain(&slot, data) != data || slot != data) return 0;
    if (pointer_nested(&outer, -12345, data) != 42 || outer.first != 123 ||
        outer.pair.tag != 7 || outer.pair.value != -12345 ||
        outer.pair.data != data) return 0;
    if (pointer_struct_stride(pairs, 1) != 42 ||
        pointer_struct_stride(pairs + 1, -1) != -12) return 0;
    return pointer_cast_byte(data) == ((const uint8_t *)data)[0] &&
           pointer_null_truth() == 1 && pointer_from_bits((uintptr_t)data) == data;
}

static int check_loops(void) {
    uint32_t counter = 0;
    if (pointer_loop(&counter, 12) != 12 || counter != 12) return 0;
    if (pointer_loop(&counter, 4) != 12 || counter != 12) return 0;
    return pointer_store_order(&counter) == 11 && counter == 11;
}

int main(void) {
    if (!check_signed_loads() || !check_unsigned_loads()) return 1;
    if (!check_stores()) return 2;
    if (!check_pointers()) return 3;
    if (!check_loops()) return 4;
    return 0;
}
