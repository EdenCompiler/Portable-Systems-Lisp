#include <stdint.h>

struct byte_buffer {
    uint8_t *data;
    uintptr_t length;
    uintptr_t capacity;
};

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

struct psl_arena {
    uint8_t *data;
    uintptr_t used;
    uintptr_t capacity;
};

struct psl_parsed_integer {
    uint64_t magnitude;
    uint8_t negative;
    uint8_t radix;
};

extern int emit_byte(struct byte_buffer *buffer, uint8_t byte);
extern uint32_t scan_next(struct psl_scanner *scanner,
                          struct psl_token *token);
extern uintptr_t parser_next(struct psl_parser *parser);
extern uint8_t *arena_alloc(struct psl_arena *arena, uintptr_t size,
                            uintptr_t alignment);
extern int parse_integer_token(const uint8_t *data, uintptr_t start,
                               uintptr_t length,
                               struct psl_parsed_integer *output);

int main(void) {
    uint8_t output[1] = {0};
    const uint8_t source[] = "(x)";
    struct byte_buffer buffer = {output, 0, sizeof output};
    struct psl_scanner scanner = {source, sizeof source - 1, 0, 0};
    struct psl_token token = {0};
    struct psl_ast_node nodes[4] = {{0}};
    _Alignas(16) uint8_t storage[32] = {0};
    struct psl_arena arena = {storage, 0, sizeof storage};
    struct psl_parsed_integer integer = {0};

    if (!emit_byte(&buffer, 42) || output[0] != 42) return 1;
    if (scan_next(&scanner, &token) != 1 || token.start != 0) return 2;
    if (scan_next(&scanner, &token) != 8 || token.start != 1) return 3;
    if (scan_next(&scanner, &token) != 2 || token.start != 2) return 4;
    if (scan_next(&scanner, &token) != 0) return 5;
    scanner.cursor = 0;
    struct psl_parser parser = {&scanner, &token, 0, nodes, 0, 4, 0};
    if (parser_next(&parser) != 1 || parser.error != 0) return 6;
    if (nodes[0].kind != 1 || nodes[0].first != 2 ||
        nodes[1].kind != 8) return 7;
    if (arena_alloc(&arena, 8, 8) != storage || arena.used != 8) return 8;
    if (parse_integer_token((const uint8_t *)"#x2a", 0, 4,
                            &integer) != 1 || integer.magnitude != 42)
        return 9;
    return 0;
}
