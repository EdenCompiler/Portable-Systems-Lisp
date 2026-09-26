#include "../bootstrap/native_api.h"

int main(void) {
    struct native_hir_node nodes[3] = {
        {1, 1, 20, 0, 0, 0, 1, 1, 0},
        {1, 1, 22, 0, 0, 0, 2, 1, 0},
        {4, 1, 0, 1, 2, 0, 3, 1, 0},
    };
    struct native_hir_arena arena = {nodes, 3, 3, 0};
    struct native_function functions[1] = {{0, 0, 0, 0, 0, 0}};
    struct native_hir_node control_nodes[5] = {
        {1, 1, 4, 0, 0, 0, 1, 1, 0},
        {1, 1, 5, 0, 0, 0, 2, 1, 0},
        {9, 2, 0, 1, 2, 0, 3, 0, 0},
        {1, 1, 42, 0, 0, 0, 4, 1, 0},
        {10, 1, 0, 3, 4, 1, 5, 1, 0},
    };
    struct native_hir_arena control = {control_nodes, 5, 5, 0};
    struct native_hir_node lexical_nodes[5] = {
        {1, 1, 42, 0, 0, 0, 1, 1, 0},
        {14, 1, 1, 1, 0, 0, 2, 1, 0},
        {15, 1, 0, 0, 0, 2, 3, 1, 0},
        {16, 1, 0, 2, 3, 0, 4, 1, 0},
        {13, 1, 0, 4, 3, 0, 5, 1, 0},
    };
    struct native_hir_arena lexical = {lexical_nodes, 5, 5, 0};

    if (!hir_verify_root(&arena, 3, functions, 0, 0)) return 1;
    nodes[2].kind = 11;
    if (!hir_verify_root(&arena, 3, functions, 0, 0)) return 14;
    nodes[2].kind = 12;
    if (!hir_verify_root(&arena, 3, functions, 0, 0)) return 15;
    nodes[2].kind = 4;
    nodes[2].right = 3;
    if (hir_verify_root(&arena, 3, functions, 0, 0)) return 2;
    nodes[2].right = 2;
    nodes[2].target = 1;
    if (hir_verify_root(&arena, 3, functions, 0, 0)) return 3;
    nodes[2].target = 0;
    nodes[0].type_code = 2;
    if (hir_verify_root(&arena, 3, functions, 0, 0)) return 4;
    nodes[0].type_code = 1;
    nodes[0].kind = 2;
    nodes[0].value = 2;
    if (hir_verify_root(&arena, 3, functions, 0, 1)) return 5;
    if (!hir_verify_root(&arena, 3, functions, 0, 2)) return 6;
    nodes[0].kind = 1;
    nodes[0].value = 20;
    nodes[2] = (struct native_hir_node){7, 1, 0, 0, 0, 1, 3, 1, 0};
    if (hir_verify_root(&arena, 3, functions, 0, 0)) return 7;
    if (!hir_verify_root(&arena, 3, functions, 1, 0)) return 8;
    nodes[2].left = 1;
    if (hir_verify_root(&arena, 3, functions, 1, 0)) return 9;
    functions[0].arity = 1;
    nodes[1] = (struct native_hir_node){17, 1, 0, 1, 0, 0, 2, 1, 0};
    nodes[2].left = 2;
    if (!hir_verify_root(&arena, 3, functions, 1, 0)) return 19;
    nodes[1].right = 1;
    if (hir_verify_root(&arena, 3, functions, 1, 0)) return 20;
    nodes[1].right = 0;
    nodes[1].kind = 1;
    if (hir_verify_root(&arena, 3, functions, 1, 0)) return 21;
    nodes[1].kind = 17;
    nodes[0].type_code = 2;
    if (hir_verify_root(&arena, 3, functions, 1, 0)) return 22;
    nodes[0].type_code = 1;
    if (!hir_verify_root(&control, 5, functions, 0, 0)) return 10;
    if (hir_verify_root(&control, 3, functions, 0, 0)) return 11;
    control_nodes[2].type_code = 1;
    if (hir_verify_root(&control, 5, functions, 0, 0)) return 12;
    control_nodes[2].type_code = 2;
    control.error = 1;
    if (hir_verify_root(&control, 5, functions, 0, 0)) return 13;
    if (!hir_verify_root(&lexical, 4, functions, 0, 0)) return 16;
    if (hir_verify_root(&lexical, 5, functions, 0, 0)) return 17;
    lexical_nodes[1].value = 6;
    if (hir_verify_root(&lexical, 4, functions, 0, 0)) return 18;

    struct native_compile_context typed = {0};
    typed.hir = &arena;
    nodes[0] = (struct native_hir_node){1, 1, 20, 0, 0, 0, 1, 3, 0};
    nodes[1] = (struct native_hir_node){1, 1, 22, 0, 0, 0, 2, 3, 0};
    nodes[2] = (struct native_hir_node){4, 1, 0, 1, 2, 0, 3, 3, 0};
    if (!hir_verify_root(&arena, 3, functions, 0, 0)) return 23;
    if (!hir_verify_scalar_tree(&typed, 3, 0)) return 24;
    nodes[1].scalar_code = 1;
    if (hir_verify_scalar_tree(&typed, 3, 0)) return 25;
    nodes[1].scalar_code = 3;
    nodes[1].value = 256;
    if (hir_verify_scalar_tree(&typed, 3, 0)) return 26;
    nodes[1].value = 22;
    nodes[2] = (struct native_hir_node){18, 1, 0, 1, 0, 0, 3, 6, 0};
    if (!hir_verify_root(&arena, 3, functions, 0, 0)) return 27;
    if (!hir_verify_scalar_tree(&typed, 3, 0)) return 28;
    nodes[2].scalar_code = 0;
    if (hir_verify_scalar_tree(&typed, 3, 0)) return 29;
    nodes[2].scalar_code = 6;
    nodes[0].scalar_code = 6;
    nodes[0].value = UINT64_MAX;
    if (!hir_verify_scalar_tree(&typed, 3, 0)) return 30;
    nodes[0].value = 128;
    if (hir_verify_scalar_tree(&typed, 3, 0)) return 31;
    return 0;
}
