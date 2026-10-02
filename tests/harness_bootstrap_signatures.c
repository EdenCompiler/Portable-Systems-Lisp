#include "../bootstrap/native_api.h"
#include "../bootstrap/host/source.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int name_is(const uint8_t *source, const struct psl_ast_node *nodes,
                   uintptr_t reference, const char *expected) {
    const struct psl_ast_node *node = &nodes[reference - 1];
    size_t length = strlen(expected);
    return node->length == length &&
           memcmp(source + node->start, expected, length) == 0;
}

static const struct native_signature *find_signature(
    const struct native_signature_context *context,
    const uint8_t *source, const struct psl_ast_node *nodes,
    const char *name) {
    for (uintptr_t i = 0; i < context->signature_count; ++i) {
        if (name_is(source, nodes, context->signatures[i].name, name))
            return &context->signatures[i];
    }
    return NULL;
}

static int check_known_signature(
    const struct native_signature_context *context,
    const uint8_t *source, const struct psl_ast_node *nodes,
    const char *name, uintptr_t arity, uintptr_t result_size,
    uint32_t result_kind, int exported,
    uintptr_t last_size, uint32_t last_kind) {
    const struct native_signature *signature =
        find_signature(context, source, nodes, name);
    return signature && signature->arity == arity &&
           signature->result_size == result_size &&
           signature->result_kind == result_kind &&
           signature->exported == exported && signature->body != 0 &&
           context->parameters[signature->first_parameter].size == 8 &&
           context->parameters[signature->first_parameter].kind == 2 &&
           context->parameters[signature->first_parameter + arity - 1].size ==
               last_size &&
           context->parameters[signature->first_parameter + arity - 1].kind ==
               last_kind;
}

static int check_module(const char *path, size_t expected_functions,
                        size_t expected_layouts, const char *known_name,
                        size_t arity, size_t result_size,
                        uint32_t result_kind, int exported,
                        size_t last_size, uint32_t last_kind) {
    struct native_signature signatures[128] = {0};
    struct native_layout layouts[32] = {0};
    struct native_layout_field fields[128] = {0};
    struct native_parameter parameters[256] = {0};
    struct native_type_shape shape = {0};
    struct psl_token token = {0};
    struct psl_ast_node *nodes;
    struct psl_scanner scanner;
    struct psl_parser parser;
    struct native_layout_context layout_context;
    struct native_signature_context signature_context;
    uint8_t *source;
    uintptr_t root;
    size_t length;
    int ok = 1;

    struct native_c_source_path *c_sources = NULL;
    source = native_read_source_unit(path, &length, &c_sources);
    assert(!c_sources);
    if (!source) return 0;
    nodes = calloc(length + 1, sizeof *nodes);
    if (!nodes) { free(source); return 0; }
    scanner = (struct psl_scanner){source, length, 0, 0};
    parser = (struct psl_parser){&scanner, &token, 0, nodes, 0, length + 1, 0, NULL};
    layout_context = (struct native_layout_context){
        &parser, source, layouts, 0, 32, fields, 0, 128, &shape, 0, 0
    };
    signature_context = (struct native_signature_context){
        &layout_context, signatures, 0, 128, parameters, 0, 256, 0
    };
    while ((root = parser_next(&parser)) != 0) {
        if (native_layout_form_p(&layout_context, root))
            ok = native_register_layout(&layout_context, root);
        else
            ok = native_parse_signature(&signature_context, root);
        if (!ok) break;
    }
    ok = ok && parser.error == 0 && layout_context.error == 0 &&
         signature_context.signature_count == expected_functions &&
         layout_context.layout_count == expected_layouts &&
         check_known_signature(&signature_context, source, nodes,
                               known_name, arity, result_size,
                               result_kind, exported, last_size, last_kind);
    free(nodes);
    free(source);
    return ok;
}

static int rejected(const char *source) {
    struct psl_ast_node nodes[64] = {0};
    struct native_signature signatures[4] = {0};
    struct native_parameter parameters[8] = {0};
    struct native_layout layouts[4] = {0};
    struct native_layout_field fields[8] = {0};
    struct native_type_shape shape = {0};
    struct psl_token token = {0};
    struct psl_scanner scanner = {
        (const uint8_t *)source, strlen(source), 0, 0
    };
    struct psl_parser parser = {
        &scanner, &token, 0, nodes, 0, 64, 0, NULL
    };
    struct native_layout_context layout_context = {
        &parser, (const uint8_t *)source, layouts, 0, 4,
        fields, 0, 8, &shape, 0, 0
    };
    struct native_signature_context context = {
        &layout_context, signatures, 0, 4, parameters, 0, 8, 0
    };
    uintptr_t root = parser_next(&parser);
    return root && !native_parse_signature(&context, root);
}

int main(int argc, char **argv) {
    if (argc != 5 ||
        !check_module(argv[1], 9, 1, "emit_byte", 2, 4, 1, 1, 1, 1) ||
        !check_module(argv[2], 3, 1, "arena_alloc", 3, 8, 2, 1, 8, 1) ||
        !check_module(argv[3], 8, 1, "parse_integer_token", 4, 4, 1, 1,
                      8, 2) ||
        !check_module(argv[4], 24, 2, "scan_next", 2, 4, 1, 1, 8, 2) ||
        !rejected("(defun bad (x) (declare (returns u64)) x)") ||
        !rejected("(defun bad (x) (declare (type u64 x)) x)") ||
        !rejected("(defun bad (x x) "
                  "(declare (type u64 x) (returns u64)) x)") ||
        !rejected("(defun bad (x) "
                  "(declare (type u64 y) (returns u64)) x)") ||
        !rejected("(defun bad (x) "
                  "(declare (type u64 x) (type u64 x) "
                  "(returns u64)) x)") ||
        !rejected("(defun bad () (declare (returns (ptr missing))) 0)")) {
        fputs("native signature parsing mismatch\n", stderr);
        return 1;
    }
    return 0;
}
