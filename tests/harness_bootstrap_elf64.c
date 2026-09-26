#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct byte_buffer {
    uint8_t *data;
    uintptr_t length;
    uintptr_t capacity;
};

extern int write_elf64_single(uint16_t machine, uint32_t flags,
                              const uint8_t *code, uintptr_t code_size,
                              const uint8_t *name, uintptr_t name_size,
                              struct byte_buffer *buffer);

static uint8_t *read_file(const char *path, size_t *length) {
    FILE *stream = fopen(path, "rb");
    uint8_t *bytes;
    long size;

    if (!stream) return NULL;
    if (fseek(stream, 0, SEEK_END) != 0 || (size = ftell(stream)) < 0 ||
        fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    bytes = malloc((size_t)size + 1);
    if (!bytes || fread(bytes, 1, (size_t)size, stream) != (size_t)size) {
        free(bytes);
        fclose(stream);
        return NULL;
    }
    fclose(stream);
    *length = (size_t)size;
    return bytes;
}

int main(int argc, char **argv) {
    const char *name = "answer";
    uint8_t *code;
    uint8_t *output;
    size_t code_size;
    size_t capacity;
    uint16_t machine;
    uint32_t flags;
    struct byte_buffer buffer;
    FILE *stream;

    if (argc != 5) return 1;
    machine = (uint16_t)strtoul(argv[3], NULL, 0);
    flags = (uint32_t)strtoul(argv[4], NULL, 0);
    code = read_file(argv[1], &code_size);
    if (!code) return 2;
    capacity = code_size + 4096;
    output = calloc(capacity, 1);
    if (!output) {
        free(code);
        return 3;
    }
    buffer = (struct byte_buffer){output, 0, capacity};
    struct byte_buffer too_small = {output, 0, 8};
    const uint8_t invalid_name[] = {0x80};
    if (write_elf64_single(machine, flags, code, code_size,
                           (const uint8_t *)name,
                           strlen(name), &too_small) || too_small.length != 0 ||
        write_elf64_single(machine, flags, code, code_size,
                           invalid_name, 1, &buffer) ||
        buffer.length != 0 ||
        write_elf64_single(machine, flags, code, code_size,
                           (const uint8_t *)name, 0,
                           &buffer) || buffer.length != 0) {
        free(code);
        free(output);
        return 4;
    }
    if (!write_elf64_single(machine, flags, code, code_size,
                            (const uint8_t *)name,
                            strlen(name), &buffer)) {
        free(code);
        free(output);
        return 5;
    }
    stream = fopen(argv[2], "wb");
    if (!stream) {
        free(code);
        free(output);
        return 6;
    }
    if (fwrite(output, 1, buffer.length, stream) != buffer.length) {
        fclose(stream);
        free(code);
        free(output);
        return 7;
    }
    fclose(stream);
    free(code);
    free(output);
    return 0;
}
