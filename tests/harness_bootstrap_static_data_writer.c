#include "../bootstrap/native_api.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const uint8_t hidden_bytes[] = {0x91, 0x82, 0x73};
static const uint8_t message_bytes[] = "Portable Systems Lisp";
static const uint8_t word_bytes[] = {0x88, 0x77, 0x66, 0x55,
                                     0x44, 0x33, 0x22, 0x11};

static struct native_data_symbol symbols[] = {
    {(const uint8_t *)"psl_hidden_blob", 15, hidden_bytes,
     sizeof hidden_bytes, 1, 0},
    {(const uint8_t *)"psl_message", 11, message_bytes,
     sizeof message_bytes, 1, 1},
    {(const uint8_t *)"psl_aligned_word", 16, word_bytes,
     sizeof word_bytes, 16, 1},
};

static int write_object(const char *format, struct native_data_symbol *items,
                        uintptr_t count, struct byte_buffer *buffer,
                        uint16_t machine, uint32_t flags) {
    if (strcmp(format, "elf") == 0)
        return write_elf64_data(machine, flags, items, count, buffer);
    if (strcmp(format, "coff") == 0)
        return write_coff64_data(items, count, buffer);
    return 0;
}

static int rejects_bad_inputs(const char *format, uint8_t *output,
                              size_t capacity, uint16_t machine,
                              uint32_t flags) {
    struct byte_buffer buffer = {output, 0, capacity};
    struct native_data_symbol saved = symbols[0];

    if (write_object(format, symbols, 0, &buffer, machine, flags) || buffer.length)
        return 0;
    buffer.capacity = 8;
    if (write_object(format, symbols, 3, &buffer, machine, flags) || buffer.length)
        return 0;
    buffer.capacity = capacity;
    symbols[0].alignment = 3;
    if (write_object(format, symbols, 3, &buffer, machine, flags) || buffer.length)
        return 0;
    symbols[0] = saved;
    symbols[0].name = symbols[1].name;
    symbols[0].name_length = symbols[1].name_length;
    if (write_object(format, symbols, 3, &buffer, machine, flags) || buffer.length)
        return 0;
    symbols[0] = saved;
    symbols[0].name = NULL;
    if (write_object(format, symbols, 3, &buffer, machine, flags) || buffer.length)
        return 0;
    symbols[0] = saved;
    symbols[0].bytes = NULL;
    if (write_object(format, symbols, 3, &buffer, machine, flags) || buffer.length)
        return 0;
    symbols[0] = saved;
    symbols[0].size = (uintptr_t)-1;
    if (write_object(format, symbols, 3, &buffer, machine, flags) || buffer.length)
        return 0;
    symbols[0] = saved;
    symbols[0].exported = 2;
    if (write_object(format, symbols, 3, &buffer, machine, flags) || buffer.length)
        return 0;
    symbols[0] = saved;
    return 1;
}

int main(int argc, char **argv) {
    uint16_t machine = 0;
    uint32_t flags = 0;
    uint8_t *output;
    struct byte_buffer buffer;
    FILE *stream;

    if (argc != 3 && argc != 5) return 1;
    if (argc == 5) {
        machine = (uint16_t)strtoul(argv[3], NULL, 0);
        flags = (uint32_t)strtoul(argv[4], NULL, 0);
    }
    output = calloc(16384, 1);
    if (!output) return 2;
    if (!rejects_bad_inputs(argv[1], output, 16384, machine, flags)) {
        free(output);
        return 3;
    }
    buffer = (struct byte_buffer){output, 0, 16384};
    if (!write_object(argv[1], symbols, 3, &buffer, machine, flags)) {
        free(output);
        return 4;
    }
    stream = fopen(argv[2], "wb");
    if (!stream) {
        free(output);
        return 5;
    }
    if (fwrite(output, 1, buffer.length, stream) != buffer.length ||
        fclose(stream) != 0) {
        free(output);
        return 6;
    }
    free(output);
    return 0;
}
