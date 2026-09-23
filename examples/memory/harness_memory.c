#include <stddef.h>
#include <stdint.h>
#include <string.h>

struct __attribute__((packed)) packet {
    uint8_t tag;
    uint16_t count;
    uint32_t payload;
};

extern size_t packet_size(void);
extern size_t packet_alignment(void);
extern size_t payload_offset(void);
extern uint8_t read_tag(const struct packet *);
extern uint32_t read_payload(const struct packet *);
extern uint16_t write_count(struct packet *, uint16_t);
extern uint8_t second_byte(const uint8_t *);
extern uint16_t second_word(const uint16_t *);
extern uint8_t first_byte_via_cast(const struct packet *);
extern uint8_t read_address(uintptr_t);
extern int8_t read_signed_byte(const int8_t *);
extern uint8_t wrap_byte(uint8_t);
extern uint8_t previous_byte(const uint8_t *);
extern uint8_t read_status(const volatile uint8_t *);

_Static_assert(sizeof(struct packet) == 7, "packed size");
_Static_assert(_Alignof(struct packet) == 1, "packed alignment");
_Static_assert(offsetof(struct packet, payload) == 3, "packed offset");

int main(void) {
    struct packet value = { .tag = 9, .count = 1, .payload = 0x12345678u };
    uint8_t bytes[] = { 5, 42 };
    uint16_t words[] = { 5, 4242 };
    int8_t signed_byte = -7;
    volatile uint8_t status = 42;
    uint16_t count;
    if (packet_size() != sizeof value) return 1;
    if (packet_alignment() != _Alignof(struct packet)) return 2;
    if (payload_offset() != offsetof(struct packet, payload)) return 3;
    if (read_tag(&value) != 9) return 4;
    if (read_payload(&value) != 0x12345678u) return 5;
    if (write_count(&value, 42) != 42) return 6;
    memcpy(&count, (const uint8_t *)&value + offsetof(struct packet, count),
           sizeof count);
    if (count != 42) return 7;
    if (second_byte(bytes) != 42) return 8;
    if (second_word(words) != 4242) return 9;
    if (first_byte_via_cast(&value) != 9) return 10;
    if (read_address((uintptr_t)&bytes[1]) != 42) return 11;
    if (read_signed_byte(&signed_byte) != -7) return 12;
    if (wrap_byte(255) != 0) return 13;
    if (previous_byte(&bytes[1]) != 5) return 14;
    if (read_status(&status) != 42) return 15;
    return 0;
}
