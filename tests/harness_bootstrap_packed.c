#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#pragma pack(push, 1)
struct packed_packet {
    uint8_t tag;
    uint64_t value;
    int16_t delta;
    uint8_t *address;
};
struct packed_outer {
    uint8_t prefix;
    struct packed_packet packet;
    uint32_t tail;
};
#pragma pack(pop)

struct natural_pair { uint8_t tag; uint32_t value; };
#pragma pack(push, 1)
struct packed_bridge { uint8_t head; struct natural_pair pair; uint8_t tail; };
#pragma pack(pop)

extern uintptr_t packed_packet_size(void);
extern uintptr_t packed_packet_alignment(void);
extern uintptr_t packed_packet_address_offset(void);
extern uintptr_t packed_outer_size(void);
extern uintptr_t packed_bridge_size(void);
extern uintptr_t packed_bridge_tail(void);
extern uint64_t packed_update(struct packed_packet *, uint64_t, int16_t, uint8_t *);
extern uint64_t packed_nested_read(struct packed_outer *);
extern uint8_t *packed_read_address(struct packed_packet *);

int main(void) {
    assert(packed_packet_size() == sizeof(struct packed_packet));
    assert(packed_packet_alignment() == _Alignof(struct packed_packet));
    assert(packed_packet_address_offset() == offsetof(struct packed_packet, address));
    assert(packed_outer_size() == sizeof(struct packed_outer));
    assert(packed_bridge_size() == sizeof(struct packed_bridge));
    assert(packed_bridge_tail() == offsetof(struct packed_bridge, tail));
    uint8_t memory[sizeof(struct packed_outer) + 1];
    memset(memory, 0xa5, sizeof memory);
    struct packed_outer *outer = (struct packed_outer *)(memory + 1);
    uint8_t byte = 42;
    assert(packed_update(&outer->packet, UINT64_C(0xfffffffffffffff0), -7, &byte)
           == UINT64_C(0xffffffffffffffe9));
    assert(outer->prefix == 0xa5 && outer->packet.tag == 0xa5);
    assert(outer->packet.value == UINT64_C(0xfffffffffffffff0));
    assert(outer->packet.delta == -7 && outer->packet.address == &byte);
    assert(outer->tail == UINT32_C(0xa5a5a5a5) && memory[0] == 0xa5);
    assert(packed_nested_read(outer) == UINT64_C(0xfffffffffffffff0));
    assert(packed_read_address(&outer->packet) == &byte);
    return 0;
}
