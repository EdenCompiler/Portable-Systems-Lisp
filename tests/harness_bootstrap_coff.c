#include "../bootstrap/native_api.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern uintptr_t win64_frame_bytes(uintptr_t values, uintptr_t outgoing);
extern uintptr_t win64_function_prologue(struct byte_buffer *, uintptr_t, uintptr_t);
extern int win64_return(struct byte_buffer *, uintptr_t);
extern int emit_integer(struct byte_buffer *, uint64_t, uintptr_t);

static uint8_t machine_code[256], object_data[4096];
enum { MANY_CALLS = 65536 };
static uint8_t large_code[5 * MANY_CALLS + 128];
static uint8_t large_object[2 * 1024 * 1024];
static struct native_call_fixup large_fixups[MANY_CALLS];
static struct native_function functions[2];
static struct native_call_fixup call;
static struct native_fixup_arena fixups;
static struct byte_buffer code = {machine_code, 0, sizeof machine_code};
static struct byte_buffer object = {object_data, 0, sizeof object_data};

static int rejected(void) {
    object.length = 0;
    return !write_coff64_calls(code.data, code.length, functions, 2, &fixups, &object) &&
           object.length == 0;
}

static int prepare(void) {
    uintptr_t frame = win64_frame_bytes(0, 32);
    uintptr_t prologue = win64_function_prologue(&code, frame, 32);
    if (!frame || !prologue) return 0;
    call.instruction = code.length;
    call.target = 2;
    if (!emit_integer(&code, 0xe8, 1) || !emit_integer(&code, 0, 4) ||
        !win64_return(&code, frame)) return 0;
    functions[0] = (struct native_function){
        .name = (const uint8_t *)"test_answer", .name_length = 11,
        .offset = 0, .size = code.length, .exported = 1,
        .frame_size = frame, .prologue_size = prologue
    };
    functions[1] = (struct native_function){
        .name = (const uint8_t *)"foreign_return_42", .name_length = 17,
        .imported = 1, .referenced = 1
    };
    fixups = (struct native_fixup_arena){.items = &call, .count = 1, .capacity = 1};
    return 1;
}

static int check_rejections(void) {
    uintptr_t saved;
    uint8_t old_byte;
    uintptr_t original_length = object.length;
    if (write_coff64_calls(code.data, code.length, functions, 2, &fixups, &object) ||
        object.length != original_length) return 0;
    saved = call.target;
    call.target = 3;
    if (!rejected()) return 0;
    call.target = saved;
    saved = call.instruction;
    call.instruction = 0;
    if (!rejected()) return 0;
    call.instruction = saved;
    old_byte = code.data[call.instruction];
    code.data[call.instruction] = 0x90;
    if (!rejected()) return 0;
    code.data[call.instruction] = old_byte;
    old_byte = code.data[0];
    code.data[0] = 0x90;
    if (!rejected()) return 0;
    code.data[0] = old_byte;
    saved = functions[0].frame_size;
    functions[0].frame_size = 0;
    if (!rejected()) return 0;
    functions[0].frame_size = saved;
    saved = functions[0].prologue_size;
    functions[0].prologue_size = 12;
    if (!rejected()) return 0;
    functions[0].prologue_size = saved;
    functions[1].prologue_size = 1;
    if (!rejected()) return 0;
    functions[1].prologue_size = 0;
    functions[1].referenced = 0;
    if (!rejected()) return 0;
    functions[1].referenced = 1;
    functions[1].name = functions[0].name;
    functions[1].name_length = functions[0].name_length;
    if (!rejected()) return 0;
    functions[1].name = (const uint8_t *)"foreign_return_42";
    functions[1].name_length = 17;
    object.capacity = 8;
    if (!rejected()) return 0;
    object.capacity = sizeof object_data;
    fixups.count = 2;
    if (!rejected()) return 0;
    fixups.count = 1;
    if (!write_coff64_calls(code.data, code.length, functions, 2, &fixups, &object)) return 0;
    uintptr_t length = object.length;
    if (write_coff64_calls(code.data, code.length, functions, 2, &fixups, &object) ||
        object.length != length) return 0;
    struct byte_buffer elf = {object_data, 0, sizeof object_data};
    return !write_elf64_calls_target(NATIVE_TARGET_X86_64_WINDOWS, code.data, code.length,
                                     functions, 2, &fixups, &elf) && elf.length == 0;
}

static uint32_t read_word(const uint8_t *data) {
    return (uint32_t)data[0] | (uint32_t)data[1] << 8 |
           (uint32_t)data[2] << 16 | (uint32_t)data[3] << 24;
}

static int write_overflow_object(const char *path) {
    code = (struct byte_buffer){large_code, 0, sizeof large_code};
    uintptr_t frame = win64_frame_bytes(0, 32);
    uintptr_t prologue = win64_function_prologue(&code, frame, 32);
    if (!prologue) return 0;
    for (uintptr_t i = 0; i < MANY_CALLS; ++i) {
        large_fixups[i] = (struct native_call_fixup){code.length, 2};
        if (!emit_integer(&code, 0xe8, 1) || !emit_integer(&code, 0, 4)) return 0;
    }
    if (!win64_return(&code, frame)) return 0;
    functions[0].size = code.length;
    fixups = (struct native_fixup_arena){large_fixups, MANY_CALLS, MANY_CALLS, 0};
    object = (struct byte_buffer){large_object, 0, sizeof large_object};
    if (!write_coff64_calls(code.data, code.length, functions, 2, &fixups, &object)) return 0;
    uint32_t relocation_offset = read_word(object.data + 44);
    if (object.data[52] != 0xff || object.data[53] != 0xff ||
        !(read_word(object.data + 56) & 0x01000000) ||
        read_word(object.data + relocation_offset) != MANY_CALLS + 1 ||
        read_word(object.data + relocation_offset + 4) != 0 ||
        read_word(object.data + relocation_offset + 10) != large_fixups[0].instruction + 1)
        return 0;
    FILE *stream = fopen(path, "wb");
    if (!stream) return 0;
    int ok = fwrite(object.data, 1, object.length, stream) == object.length;
    if (fclose(stream)) ok = 0;
    return ok;
}

int main(int argc, char **argv) {
    if ((argc != 2 && argc != 3) || !prepare()) return 1;
    if (!write_coff64_calls(code.data, code.length, functions, 2, &fixups, &object)) return 2;
    if (!check_rejections()) return 3;
    FILE *stream = fopen(argv[1], "wb");
    if (!stream) return 4;
    int ok = fwrite(object.data, 1, object.length, stream) == object.length;
    if (fclose(stream)) ok = 0;
    if (!ok) return 5;
    return argc == 3 && !write_overflow_object(argv[2]) ? 6 : 0;
}
