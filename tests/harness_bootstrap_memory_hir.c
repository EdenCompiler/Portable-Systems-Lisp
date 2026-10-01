#include "../bootstrap/native_api.h"

static int valid(struct native_compile_context *context, uintptr_t root) {
    return hir_verify_root(context->hir, root, 0, 0, 0) &&
           hir_verify_scalar_tree(context, root, 0);
}

int main(void) {
    static const uint8_t source[] = "u8 u16";
    struct psl_ast_node syntax[] = {
        {8, 0, 2, 0, 0, 0}, {8, 3, 3, 0, 0, 0}
    };
    struct psl_parser parser = {0};
    struct native_type_shape shape = {0};
    struct native_layout_context layouts = {0};
    struct native_signature_context signatures = {0};
    struct native_hir_node nodes[] = {
        {1, 1, 0, 0, 0, 0, 1, 2, 0, 0},  /* usize address */
        {21, 1, 0, 1, 0, 0, 1, 11, 1, 0}, /* (ptr u8) */
        {24, 1, 1, 2, 0, 0, 1, 3, 0, 0},  /* u8 load */
        {1, 1, 255, 0, 0, 0, 1, 3, 0, 0},
        {25, 1, 1, 2, 4, 0, 1, 3, 0, 0},  /* u8 store */
        {1, 1, 1, 0, 0, 0, 1, 10, 0, 0}, /* isize offset */
        {27, 1, 1, 2, 6, 0, 1, 11, 1, 0}, /* pointer+ */
    };
    struct native_hir_arena hir = {nodes, 7, 7, 0};
    struct native_compile_context context = {0};
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
    /* Constness is carried in reference metadata and forbids writes while
       leaving the same pointer valid for reads. */
    nodes[1].pointee = UINT64_C(0x4000000000000001);
    if (!valid(&context, 3) || valid(&context, 5)) return 8;
    nodes[1].pointee = 1;
    nodes[5].scalar_code = 2;
    if (valid(&context, 7)) return 6;
    nodes[5].scalar_code = 10;
    nodes[6].value = 8;
    if (valid(&context, 7)) return 7;
    /* Floating payloads have their own literal width and no integer cast. */
    nodes[3].scalar_code = 13;
    nodes[3].value = UINT32_C(0x80000000);
    if (!valid(&context, 4)) return 9;
    nodes[3].value = UINT64_C(0x100000000);
    if (valid(&context, 4)) return 10;
    nodes[3].value = 0;
    nodes[3].kind = 18;
    nodes[3].left = 1;
    if (valid(&context, 4)) return 11;
    nodes[3].kind = 1;
    nodes[3].left = 0;
    nodes[3].scalar_code = 14;
    nodes[3].value = UINT64_C(0x8000000000000000);
    if (!valid(&context, 4)) return 12;
    nodes[3].pointee = 1;
    if (valid(&context, 4)) return 13;
    return 0;
}
