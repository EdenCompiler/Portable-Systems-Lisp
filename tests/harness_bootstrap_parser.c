#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct psl_scanner {
    const uint8_t *data;
    uintptr_t length;
    uintptr_t cursor;
    uint8_t error;
};

struct psl_token {
    uint32_t kind;
    uintptr_t start;
    uintptr_t length;
};

struct psl_ast_node {
    uint32_t kind;
    uintptr_t start;
    uintptr_t length;
    uintptr_t first;
    uintptr_t last;
    uintptr_t next;
};

struct psl_parser {
    struct psl_scanner *scanner;
    struct psl_token *token;
    uint8_t has_token;
    struct psl_ast_node *nodes;
    uintptr_t count;
    uintptr_t capacity;
    uint32_t error;
};

extern uintptr_t parser_next(struct psl_parser *parser);

static struct psl_parser make_parser(const char *source,
                                      struct psl_scanner *scanner,
                                      struct psl_token *token,
                                      struct psl_ast_node *nodes,
                                      uintptr_t capacity) {
    *scanner = (struct psl_scanner){
        (const uint8_t *)source, strlen(source), 0, 0
    };
    *token = (struct psl_token){0};
    return (struct psl_parser){scanner, token, 0, nodes, 0, capacity, 0};
}

static int check_tree(void) {
    const char *source = "(add 1 (wrap+ 2 3))";
    struct psl_scanner scanner;
    struct psl_token token;
    struct psl_ast_node nodes[16] = {{0}};
    struct psl_parser parser = make_parser(source, &scanner, &token, nodes, 16);

    if (parser_next(&parser) != 1 || parser.error) return 1;
    if (parser_next(&parser) != 0 || parser.error) return 2;
    if (parser.count != 7) return 3;
    if (nodes[0].kind != 1 || nodes[0].length != strlen(source) ||
        nodes[0].first != 2 || nodes[0].last != 4) return 4;
    if (nodes[1].kind != 8 || nodes[1].next != 3 ||
        memcmp(source + nodes[1].start, "add", 3) != 0) return 5;
    if (nodes[2].next != 4 || nodes[3].kind != 1 ||
        nodes[3].first != 5 || nodes[3].last != 7) return 6;
    if (nodes[4].next != 6 || nodes[5].next != 7 ||
        nodes[6].next != 0) return 7;
    return 0;
}

static int check_prefix(void) {
    struct psl_scanner scanner;
    struct psl_token token;
    struct psl_ast_node nodes[8] = {{0}};
    struct psl_parser parser = make_parser("'x", &scanner, &token, nodes, 8);

    if (parser_next(&parser) != 1 || parser.error) return 1;
    if (nodes[0].kind != 3 || nodes[0].first != 2 ||
        nodes[1].kind != 8 || nodes[1].start != 1) return 2;
    return 0;
}

static int check_error(const char *source, uint32_t expected,
                       uintptr_t capacity) {
    struct psl_scanner scanner;
    struct psl_token token;
    struct psl_ast_node nodes[8] = {{0}};
    struct psl_parser parser = make_parser(source, &scanner, &token,
                                           nodes, capacity);

    uintptr_t node = parser_next(&parser);
    if (node == 0 && parser.error == expected) return 0;
    fprintf(stderr, "parse error mismatch: %s node=%lu error=%u expected=%u\n",
            source, (unsigned long)node, parser.error, expected);
    return 1;
}

static int check_file(const char *path) {
    FILE *stream = fopen(path, "rb");
    uint8_t *source;
    struct psl_ast_node *nodes;
    struct psl_scanner scanner;
    struct psl_token token;
    struct psl_parser parser;
    long size;

    if (!stream) return 1;
    if (fseek(stream, 0, SEEK_END) != 0 || (size = ftell(stream)) < 0 ||
        fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return 2;
    }
    source = malloc((size_t)size + 1);
    nodes = calloc((size_t)size + 1, sizeof *nodes);
    if (!source || !nodes) {
        free(source);
        free(nodes);
        fclose(stream);
        return 3;
    }
    if (fread(source, 1, (size_t)size, stream) != (size_t)size) {
        free(source);
        free(nodes);
        fclose(stream);
        return 4;
    }
    fclose(stream);
    source[size] = 0;
    parser = make_parser((const char *)source, &scanner, &token, nodes,
                         (uintptr_t)size + 1);
    while (parser_next(&parser) != 0) {}
    free(source);
    free(nodes);
    return parser.error == 0 ? 0 : 5;
}

int main(int argc, char **argv) {
    if (check_tree()) return 1;
    if (check_prefix()) return 2;
    if (check_error("(x", 3, 8)) return 3;
    if (check_error(")", 2, 8)) return 4;
    if (check_error("(x)", 4, 1)) return 5;
    if (check_error("\"unterminated", 1, 8)) return 6;
    for (int i = 1; i < argc; ++i) {
        if (check_file(argv[i])) return 7;
    }
    return 0;
}
