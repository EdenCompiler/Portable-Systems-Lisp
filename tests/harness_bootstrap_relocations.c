#include "../bootstrap/native_api.h"
#include <string.h>

static int rejected_target(uint32_t target, const uint8_t *code, uintptr_t size,
                     struct native_function *functions, uintptr_t count,
                     struct native_fixup_arena *fixups) {
    uint8_t bytes[2048];
    memset(bytes, 0x7f, sizeof bytes);
    struct byte_buffer output = {bytes, 0, sizeof bytes};
    return !write_elf64_calls_target(target, code, size, functions, count, fixups, &output)
        && output.length == 0 && bytes[0] == 0x7f;
}

static int rejected(const uint8_t *code, uintptr_t size,
                    struct native_function *functions, uintptr_t count,
                    struct native_fixup_arena *fixups) {
    return rejected_target(NATIVE_TARGET_X86_64_LINUX, code, size, functions, count, fixups);
}

static int check_aarch64(void) {
    /* BL placeholder followed by RET, supplied independently of the encoder. */
    uint8_t code[] = {0, 0, 0, 0x94, 0xc0, 3, 0x5f, 0xd6};
    struct native_function functions[] = {
        {.name=(const uint8_t *)"imported", .name_length=8, .imported=1, .referenced=1},
        {.name=(const uint8_t *)"caller", .name_length=6, .size=sizeof code, .exported=1}
    };
    struct native_call_fixup fixup = {0, 1};
    struct native_fixup_arena fixups = {&fixup, 1, 1, 0};
    uint8_t bytes[2048];
    struct byte_buffer output = {bytes, 0, sizeof bytes};
    if (!write_elf64_calls_target(NATIVE_TARGET_AARCH64_LINUX, code, sizeof code,
                                  functions, 2, &fixups, &output)) return 0;
    if (!rejected_target(UINT32_MAX, code, sizeof code, functions, 2, &fixups)) return 0;
    fixup.instruction = 1;
    if (!rejected_target(1, code, sizeof code, functions, 2, &fixups)) return 0;
    fixup.instruction = 0;
    code[0] = 1; /* Imported calls must have an unpatched immediate. */
    if (!rejected_target(1, code, sizeof code, functions, 2, &fixups)) return 0;
    code[0] = 0;
    code[3] = 0x14; /* B is not BL. */
    if (!rejected_target(1, code, sizeof code, functions, 2, &fixups)) return 0;
    code[3] = 0x94;
    functions[1].size = 7;
    if (!rejected_target(1, code, sizeof code, functions, 2, &fixups)) return 0;
    functions[1].size = 4;
    functions[1].offset = 1;
    return rejected_target(1, code, sizeof code, functions, 2, &fixups);
}

static int check_riscv64(void) {
    /* AUIPC ra,0; JALR ra,ra,0; RET, independent of the PSL encoder. */
    uint8_t code[] = {0x97, 0, 0, 0, 0xe7, 0x80, 0, 0, 0x67, 0x80, 0, 0};
    struct native_function functions[] = {
        {.name=(const uint8_t *)"imported", .name_length=8, .imported=1, .referenced=1},
        {.name=(const uint8_t *)"caller", .name_length=6, .size=sizeof code, .exported=1}
    };
    struct native_call_fixup fixup = {0, 1};
    struct native_fixup_arena fixups = {&fixup, 1, 1, 0};
    uint8_t bytes[2048];
    struct byte_buffer output = {bytes, 0, sizeof bytes};
    if (!write_elf64_calls_target(NATIVE_TARGET_RISCV64_LINUX, code, sizeof code,
                                  functions, 2, &fixups, &output)) return 0;
    if (bytes[18] != 243 || bytes[48] != 4) return 0;
    fixup.instruction = 1;
    if (!rejected_target(2, code, sizeof code, functions, 2, &fixups)) return 0;
    fixup.instruction = 0;
    code[2] = 1; /* Imported AUIPC must have a zero immediate. */
    if (!rejected_target(2, code, sizeof code, functions, 2, &fixups)) return 0;
    code[2] = 0;
    code[7] = 1; /* Imported JALR must also have a zero immediate. */
    if (!rejected_target(2, code, sizeof code, functions, 2, &fixups)) return 0;
    code[7] = 0;
    code[5] = 0; /* JALR's source must match the AUIPC return-address register. */
    if (!rejected_target(2, code, sizeof code, functions, 2, &fixups)) return 0;
    code[5] = 0x80;
    functions[1].size = 4;
    if (!rejected_target(2, code, 4, functions, 2, &fixups)) return 0;
    return rejected_target(2, code, UINTPTR_MAX, functions, 2, &fixups);
}

int main(void) {
    if (!check_aarch64()) return 15;
    if (!check_riscv64()) return 16;
    uint8_t code[] = {0xe8, 0, 0, 0, 0, 0xc3};
    struct native_function functions[] = {
        {.name=(const uint8_t *)"imported", .name_length=8, .imported=1, .referenced=1},
        {.name=(const uint8_t *)"caller", .name_length=6, .size=sizeof code, .exported=1}
    };
    struct native_call_fixup fixup = {0, 1};
    struct native_fixup_arena fixups = {&fixup, 1, 1, 0};
    uint8_t bytes[2048];
    struct byte_buffer output = {bytes, 0, sizeof bytes};
    if (!write_elf64_calls(code, sizeof code, functions, 2, &fixups, &output)) return 1;
    fixup.target = 3;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 2;
    fixup.target = 0;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 3;
    fixup.target = 1;
    fixup.instruction = sizeof code - 4;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 4;
    fixup.instruction = UINTPTR_MAX;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 5;
    fixup.instruction = 0;
    code[0] = 0x90;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 6;
    code[0] = 0xe8;
    code[1] = 1;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 7;
    code[1] = 0;
    functions[0].size = 1;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 8;
    functions[0].size = 0;
    functions[0].imported = 2;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 9;
    functions[0].imported = 1;
    functions[0].referenced = 0;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 12;
    functions[0].referenced = 1;
    fixups.count = 0;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 13;
    fixups.count = 1;
    fixups.capacity = 0;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 10;
    fixups.capacity = 1;
    fixups.error = 1;
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 11;
    fixups.error = 0;
    struct native_call_fixup duplicates[] = {{0, 1}, {0, 1}};
    fixups = (struct native_fixup_arena){duplicates, 2, 2, 0};
    if (!rejected(code, sizeof code, functions, 2, &fixups)) return 14;
    return 0;
}
