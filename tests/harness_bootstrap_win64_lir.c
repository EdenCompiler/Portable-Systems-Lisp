#include "../bootstrap/native_api.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#endif

extern uintptr_t parser_next(struct psl_parser *parser);
extern int native_parse_signature(struct native_signature_context *context, uintptr_t root);
extern int predeclare_scalar_form(struct native_compile_context *context,
                                  struct native_signature *signature,
                                  struct native_function *function);
extern int compile_scalar_form(struct native_compile_context *context,
                               struct native_signature *signature,
                               struct native_function *function);
extern int emit_lir_win64_function(struct native_compile_context *context);

enum { CAPACITY = 512 };
static struct psl_ast_node syntax[CAPACITY];
static struct native_hir_node hir_nodes[CAPACITY];
static struct native_ssa_value ssa_values[CAPACITY];
static struct native_ssa_block ssa_blocks[CAPACITY];
static struct native_ir_type types[CAPACITY];
static struct native_lir_instruction lir_instructions[4 * CAPACITY];
static struct native_lir_block lir_blocks[3 * CAPACITY];
static struct native_call_fixup calls[CAPACITY], jumps[3 * CAPACITY];
static uintptr_t bindings[CAPACITY], labels[3 * CAPACITY];
static uint8_t bytes[32768];

typedef uint64_t (
#ifdef _WIN32
    *win64_function
#else
    __attribute__((ms_abi)) *win64_function
#endif
)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);

static uint8_t *allocate_executable(size_t size) {
#ifdef _WIN32
    return VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
#else
    void *memory = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return memory == MAP_FAILED ? NULL : memory;
#endif
}

static void release_executable(uint8_t *memory, size_t size) {
#ifdef _WIN32
    (void)size;
    VirtualFree(memory, 0, MEM_RELEASE);
#else
    munmap(memory, size);
#endif
}

static int check_lir_body(void) {
    static const uint8_t source[] =
        "(defun choose-five (a b c d e)"
        " (declare (type u64 a b c d e) (returns u64))"
        " (if (< a b) (wrap+ a e) (wrap- c d)))";
    struct psl_scanner scanner = {source, sizeof source - 1, 0, 0};
    struct psl_token token = {0};
    struct psl_parser parser = {&scanner, &token, 0, syntax, 0, CAPACITY, 0, NULL};
    struct psl_parsed_integer integer = {0};
    struct native_type_shape shape = {0};
    struct native_layout_context layouts = {&parser, source, NULL, 0, 0,
                                             NULL, 0, 0, &shape, 0, 0};
    struct native_signature signature = {0};
    struct native_parameter parameters[5] = {{0}};
    struct native_signature_context signatures = {&layouts, &signature, 0, 1,
                                                   parameters, 0, 5, 0};
    struct native_function function = {0};
    struct native_hir_arena hir = {hir_nodes, 0, CAPACITY, 0};
    struct native_ssa_arena ssa = {ssa_values, types, 0, CAPACITY,
                                   ssa_blocks, 0, CAPACITY, 0, 0};
    struct native_lir_arena lir = {lir_instructions, 0, 4 * CAPACITY,
                                   types, 0, CAPACITY, lir_blocks, 0,
                                   3 * CAPACITY, 0};
    struct native_fixup_arena call_fixups = {calls, 0, CAPACITY, 0};
    struct native_fixup_arena jump_fixups = {jumps, 0, 3 * CAPACITY, 0};
    struct byte_buffer code = {bytes, 0, sizeof bytes};
    struct native_compile_context context = {
        .parser = &parser, .source = source, .integer = &integer,
        .hir = &hir, .code = &code, .fixups = &call_fixups,
        .functions = &function, .signatures = &signatures,
        .ssa = &ssa, .bindings = bindings, .lir = &lir,
        .labels = labels, .jumps = &jump_fixups, .optimization = 0
    };
    uintptr_t root = parser_next(&parser);
    if (!root || !native_parse_signature(&signatures, root) ||
        !predeclare_scalar_form(&context, &signature, &function) ||
        !compile_scalar_form(&context, &signature, &function)) return 0;
    code.length = 0;
    call_fixups.count = 0;
    if (!emit_lir_win64_function(&context) ||
        context.backend_frame_size < 80 ||
        context.backend_prologue_size != 11 || code.length > 4096) return 0;
    uint8_t *memory = allocate_executable(4096);
    if (!memory) return 0;
    memcpy(memory, code.data, code.length);
    win64_function call = (win64_function)memory;
    int ok = call(1, 2, 30, 4, 41) == 42 &&
             call(3, 2, 50, 8, 99) == 42;
    release_executable(memory, 4096);
    return ok;
}

int main(void) {
    if (!check_lir_body()) {
        fprintf(stderr, "Win64 verified LIR emission failed\n");
        return 1;
    }
    return 0;
}
