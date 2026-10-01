#include "../bootstrap/native_api.h"
#include <stdio.h>
#include <string.h>

/* Independent in-memory API caller: no file loader or CLI driver code. */
enum { CAPACITY = 512 };
struct unit_storage {
    struct psl_ast_node syntax[CAPACITY];
    struct native_layout layouts[CAPACITY];
    struct native_layout_field fields[CAPACITY];
    struct native_parameter parameters[CAPACITY];
    struct native_signature signatures[CAPACITY];
    struct native_function functions[CAPACITY];
    struct native_hir_node hir[CAPACITY];
    struct native_ssa_value ssa[CAPACITY];
    struct native_ssa_block ssa_blocks[CAPACITY];
    struct native_ir_type types[CAPACITY];
    struct native_lir_instruction lir[6 * CAPACITY];
    struct native_lir_block lir_blocks[3 * CAPACITY];
    struct native_call_fixup calls[CAPACITY], jumps[3 * CAPACITY];
    uintptr_t bindings[CAPACITY], labels[3 * CAPACITY];
    uint8_t code[4096], object[16384];
};
static struct unit_storage storage;

static int compile_memory_target(const char *source, uint32_t target, uintptr_t object_capacity,
                           struct byte_buffer *object,
                           struct native_unit_result *result) {
    memset(&storage, 0, sizeof storage);
    struct psl_scanner scanner = {(const uint8_t *)source, strlen(source), 0, 0};
    struct psl_token token = {0};
    struct psl_parser parser = {&scanner, &token, 0, storage.syntax, 0, CAPACITY, 0};
    struct psl_parsed_integer integer = {0};
    struct native_type_shape shape = {0};
    struct native_layout_context layouts = {
        &parser, (const uint8_t *)source, storage.layouts, 0, CAPACITY,
        storage.fields, 0, CAPACITY, &shape, 0, 0
    };
    struct native_signature_context signatures = {
        &layouts, storage.signatures, 0, CAPACITY,
        storage.parameters, 0, CAPACITY, 0
    };
    struct native_hir_arena hir = {storage.hir, 0, CAPACITY, 0};
    struct native_ssa_arena ssa = {
        storage.ssa, storage.types, 0, CAPACITY, storage.ssa_blocks, 0, CAPACITY, 0, 0
    };
    struct native_lir_arena lir = {
        storage.lir, 0, 6 * CAPACITY, storage.types, 0, CAPACITY,
        storage.lir_blocks, 0, 3 * CAPACITY, 0
    };
    struct native_fixup_arena calls = {storage.calls, 0, CAPACITY, 0};
    struct native_fixup_arena jumps = {storage.jumps, 0, 3 * CAPACITY, 0};
    struct byte_buffer code = {storage.code, 0, sizeof storage.code};
    *object = (struct byte_buffer){storage.object, 0, object_capacity};
    struct native_compile_context context = {
        .parser = &parser, .source = (const uint8_t *)source, .integer = &integer,
        .hir = &hir, .code = &code, .fixups = &calls, .functions = storage.functions,
        .signatures = &signatures, .ssa = &ssa, .bindings = storage.bindings,
        .lir = &lir, .labels = storage.labels, .jumps = &jumps, .target = target
    };
    return native_compile_unit(&context, object, result);
}

static int compile_memory(const char *source, uintptr_t object_capacity,
                          struct byte_buffer *object, struct native_unit_result *result) {
    return compile_memory_target(source, NATIVE_TARGET_X86_64_LINUX,
                                 object_capacity, object, result);
}

static int check_target_failure(void) {
    struct byte_buffer object;
    struct native_unit_result result = {99, 99, 99};
    if (compile_memory_target("(defun", UINT32_MAX, sizeof storage.object, &object, &result)) return 0;
    return !object.length && result.phase == NATIVE_UNIT_TARGET && !result.form && !result.index;
}

static int check_failure(const char *source, uintptr_t phase, uintptr_t index) {
    struct native_unit_result result = {99, 99, 99};
    struct byte_buffer object;
    if (compile_memory(source, sizeof storage.object, &object, &result)) return 0;
    if (object.length || result.phase != phase) return 0;
    if (phase <= NATIVE_UNIT_SIGNATURE && !result.form) return 0;
    if ((phase == NATIVE_UNIT_PREDECLARE || phase == NATIVE_UNIT_BODY || phase == NATIVE_UNIT_ALLOCATION_EFFECT) &&
        result.index != index) return 0;
    return 1;
}

static int check_failures(void) {
    static const struct {
        const char *source;
        uintptr_t phase, index;
    } cases[] = {
        {"(defcstruct broken (x missing))", NATIVE_UNIT_LAYOUT, 0},
        {"(ffi:import-function 1 () -> u64)", NATIVE_UNIT_IMPORT, 0},
        {"(defun broken () 42)", NATIVE_UNIT_SIGNATURE, 0},
        {"", NATIVE_UNIT_COLLECTION, 0},
        {"(defun", NATIVE_UNIT_COLLECTION, 0},
        {"(defcstruct pair (x u64))"
         "(defun broken () (declare (returns pair)) 0)", NATIVE_UNIT_PREDECLARE, 0},
        {"(defun broken () (declare (returns u64)) (unknown))", NATIVE_UNIT_BODY, 0},
        {"(defun first () (declare (returns u64)) 42)"
         "(defcstruct pair (x u64))"
         "(defun broken () (declare (returns pair)) 0)", NATIVE_UNIT_PREDECLARE, 1},
        {"(defun first () (declare (returns u64)) 42)"
         "(defun broken () (declare (returns u64)) (unknown))", NATIVE_UNIT_BODY, 1},
        {"(ffi:import-function \"unknown\" () -> u64)"
         "(defun broken () (declare (returns u64)) (without-allocation (ffi:call unknown)))",
         NATIVE_UNIT_ALLOCATION_EFFECT, 1},
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; ++i) {
        if (!check_failure(cases[i].source, cases[i].phase, cases[i].index)) {
            fprintf(stderr, "unit API failure case %zu failed\n", i);
            return 0;
        }
    }
    return 1;
}

static int write_object(const char *path, const struct byte_buffer *object) {
    FILE *stream = fopen(path, "wb");
    if (!stream) return 0;
    int ok = fwrite(object->data, 1, object->length, stream) == object->length;
    if (fclose(stream)) ok = 0;
    return ok;
}

int main(int argc, char **argv) {
    const char *source =
        "(defcstruct box (number u64))\n"
        "(defun answer () (declare (returns u64) (c-export :c))"
        " (ffi:call unit_c (forty)))\n"
        "(ffi:import-function \"unit_c\" ((number u64)) -> u64)\n"
        "(defun forty () (declare (returns u64)) 40)\n";
    struct native_unit_result result = {99, 99, 99};
    struct byte_buffer object;
    if (argc != 2 || !check_failures() || !check_target_failure()) return 1;
    if (compile_memory(source, 1, &object, &result)) return 2;
    if (result.phase != NATIVE_UNIT_OBJECT || object.length) return 3;
    if (!compile_memory(source, sizeof storage.object, &object, &result)) return 4;
    if (result.phase || !object.length) return 5;
    return write_object(argv[1], &object) ? 0 : 6;
}
