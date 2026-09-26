#include <stdint.h>

struct ast_node {
    uint32_t kind;
    uintptr_t start, length, first, last, next;
};
struct parser {
    void *scanner, *token;
    uint8_t has_token;
    struct ast_node *nodes;
    uintptr_t count, capacity;
    uint32_t error;
};
struct type_shape {
    uintptr_t size, alignment;
    uint32_t kind;
    uintptr_t pointee;
};
struct layout_context {
    struct parser *parser;
    const uint8_t *source;
    void *layouts;
    uintptr_t layout_count, layout_capacity;
    void *fields;
    uintptr_t field_count, field_capacity;
    struct type_shape *scratch;
    uint32_t error;
};
struct signature_context {
    struct layout_context *layouts;
    void *signatures;
    uintptr_t signature_count, signature_capacity;
    void *parameters;
    uintptr_t parameter_count, parameter_capacity;
    uint32_t error;
};
struct hir_node {
    uint32_t kind, type_code;
    uint64_t value;
    uintptr_t left, right, target, source;
    uint32_t scalar_code;
    uintptr_t pointee;
};
struct hir_arena {
    struct hir_node *nodes;
    uintptr_t count, capacity;
    uint32_t error;
};
struct compile_context {
    struct parser *parser;
    const uint8_t *source;
    void *integer;
    struct hir_arena *hir;
    void *code, *fixups, *functions;
    struct signature_context *signatures;
    uintptr_t prior_count, current_arity;
    void *current_signature;
    uint32_t expected_type;
    uintptr_t active_binding, local_count, expected_pointee;
    void *ssa;
    uintptr_t *bindings;
    struct native_lir_arena *lir;
    uintptr_t *labels;
    struct native_fixup_arena *jumps;
};
extern int hir_verify_root(struct hir_arena *, uintptr_t, const void *,
                           uintptr_t, uintptr_t);
extern int hir_verify_scalar_tree(struct compile_context *, uintptr_t, uintptr_t);

static int valid(struct compile_context *context, uintptr_t root) {
    return hir_verify_root(context->hir, root, 0, 0, 0) &&
           hir_verify_scalar_tree(context, root, 0);
}

int main(void) {
    static const uint8_t source[] = "u8 u16";
    struct ast_node syntax[] = {
        {8, 0, 2, 0, 0, 0}, {8, 3, 3, 0, 0, 0}
    };
    struct parser parser = {0};
    struct type_shape shape = {0};
    struct layout_context layouts = {0};
    struct signature_context signatures = {0};
    struct hir_node nodes[] = {
        {1, 1, 0, 0, 0, 0, 1, 2, 0},  /* usize address */
        {21, 1, 0, 1, 0, 0, 1, 11, 1}, /* (ptr u8) */
        {24, 1, 1, 2, 0, 0, 1, 3, 0},  /* u8 load */
        {1, 1, 255, 0, 0, 0, 1, 3, 0},
        {25, 1, 1, 2, 4, 0, 1, 3, 0},  /* u8 store */
        {1, 1, 1, 0, 0, 0, 1, 10, 0}, /* isize offset */
        {27, 1, 1, 2, 6, 0, 1, 11, 1}, /* pointer+ */
    };
    struct hir_arena hir = {nodes, 7, 7, 0};
    struct compile_context context = {0};
    parser.nodes = syntax;
    parser.count = parser.capacity = 2;
    layouts.parser = &parser;
    layouts.source = source;
    layouts.scratch = &shape;
    signatures.layouts = &layouts;
    context.parser = &parser;
    context.source = source;
    context.hir = &hir;
    context.signatures = &signatures;
    if (!valid(&context, 3) || !valid(&context, 5) || !valid(&context, 7)) return 1;
    nodes[2].value = 2;
    if (valid(&context, 3)) return 2;
    nodes[2].value = 1;
    nodes[1].pointee = 2;
    if (valid(&context, 3) || valid(&context, 5) || valid(&context, 7)) return 3;
    nodes[1].pointee = UINTPTR_MAX;
    if (valid(&context, 3) || valid(&context, 5) || valid(&context, 7)) return 4;
    nodes[1].pointee = 1;
    nodes[4].right = 5;
    if (valid(&context, 5)) return 5;
    nodes[4].right = 4;
    nodes[5].scalar_code = 2;
    if (valid(&context, 7)) return 6;
    nodes[5].scalar_code = 10;
    nodes[6].value = 8;
    if (valid(&context, 7)) return 7;
    return 0;
}
