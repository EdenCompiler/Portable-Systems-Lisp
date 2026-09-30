#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

void *native_host_stderr(void) {
    return stderr;
}

void native_host_write_usize(void *stream, uintptr_t value) {
    fprintf(stream, "%" PRIuPTR, value);
}

void native_host_write_c_string(void *stream, const uint8_t *text) {
    fputs((const char *)text, stream);
}

void native_host_write_bytes(void *stream, const uint8_t *bytes,
                             uintptr_t length) {
    fwrite(bytes, 1, length, stream);
}

void native_host_write_byte(void *stream, uint8_t byte) {
    fputc(byte, stream);
}
