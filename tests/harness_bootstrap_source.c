#include "../bootstrap/native_api.h"
#include <string.h>

static uint32_t parse_kind(const uint8_t *source, struct psl_parser *parser,
                           struct psl_scanner *scanner, struct psl_token *token,
                           struct psl_ast_node *nodes, uintptr_t *root) {
    *scanner = (struct psl_scanner){source, strlen((const char *)source), 0, 0};
    *parser = (struct psl_parser){scanner, token, 0, nodes, 0, 64, 0};
    *root = parser_next(parser);
    return *root ? native_source_form_kind(parser, source, *root) : 255;
}

int main(void) {
    struct psl_ast_node nodes[64];
    struct psl_scanner scanner;
    struct psl_token token;
    struct psl_parser parser;
    uintptr_t root;
    uint8_t output[64];
    const uint8_t source[] = "(include \"folder/a\\\"b\\\\c.lisp\")";
    const char expected[] = "folder/a\"b\\c.lisp";
    if (parse_kind(source, &parser, &scanner, &token, nodes, &root) != 2) return 1;
    if (native_source_include_size(&parser, source, root) != strlen(expected)) return 2;
    memset(output, 0x7f, sizeof output);
    if (native_source_include_copy(&parser, source, root, output, strlen(expected))) return 3;
    if (output[0] != 0x7f) return 4;
    if (!native_source_include_copy(&parser, source, root, output, sizeof output)) return 5;
    if (strcmp((const char *)output, expected) != 0) return 6;

    const char *bad[] = {"(include)", "(include a)", "(include \"a\" \"b\")"};
    for (unsigned i = 0; i < sizeof bad / sizeof *bad; ++i) {
        const uint8_t *text = (const uint8_t *)bad[i];
        if (parse_kind(text, &parser, &scanner, &token, nodes, &root) != 0) return 7;
        if (native_source_include_size(&parser, text, root) != 0) return 8;
        if (native_source_include_copy(&parser, text, root, output, sizeof output)) return 9;
    }
    const uint8_t ordinary[] = "(defun include_helper () (declare (returns u64)) 42)";
    if (parse_kind(ordinary, &parser, &scanner, &token, nodes, &root) != 1) return 10;
    const uint8_t *nul = (const uint8_t *)"(include \"a b\")";
    uint8_t nul_source[32];
    memcpy(nul_source, nul, strlen((const char *)nul) + 1);
    if (parse_kind(nul_source, &parser, &scanner, &token, nodes, &root) != 2) return 11;
    nul_source[11] = 0;
    if (native_source_include_copy(&parser, nul_source, root, output, sizeof output)) return 12;
    return 0;
}
