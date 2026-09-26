#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct byte_buffer {
    uint8_t *data;
    uintptr_t length;
    uintptr_t capacity;
};

extern int emit_byte(struct byte_buffer *buffer, uint8_t byte);
extern int emit_integer(struct byte_buffer *buffer, uint64_t value,
                        uintptr_t count);
extern int patch_i32(struct byte_buffer *buffer, uintptr_t offset,
                     int32_t value);
extern uint64_t low_byte_bits(uint64_t value);

int main(void) {
    uint8_t bytes[16] = {0};
    const uint8_t expected[] = {
        0x7f, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01
    };
    struct byte_buffer buffer = {bytes, 0, sizeof bytes};

    if (!emit_byte(&buffer, 0x7f)) return 1;
    if (!emit_integer(&buffer, UINT64_C(0x0102030405060708), 8)) return 2;
    if (buffer.length != sizeof expected) return 3;
    if (memcmp(bytes, expected, sizeof expected) != 0) return 4;
    if (!patch_i32(&buffer, 1, -2)) return 5;
    if (bytes[1] != 0xfe || bytes[2] != 0xff ||
        bytes[3] != 0xff || bytes[4] != 0xff) return 6;
    if (buffer.length != sizeof expected) return 7;
    if (patch_i32(&buffer, 6, -2)) return 8;
    if (emit_integer(&buffer, 0, 9)) return 9;
    if (emit_integer(&buffer, 0, 8)) return 10;
    if (buffer.length != sizeof expected) return 11;
    if (low_byte_bits(UINT64_C(0x1122334455667788)) != 0x88) return 12;
    if (fwrite(bytes, 1, buffer.length, stdout) != buffer.length) return 13;
    return 0;
}
