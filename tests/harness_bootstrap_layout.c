#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
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

struct native_type_shape {
    uintptr_t size;
    uintptr_t alignment;
    uint32_t kind;
    uintptr_t pointee;
};

struct native_layout_field {
    uintptr_t name;
    uintptr_t type_ast;
    uintptr_t offset;
    uintptr_t size;
    uintptr_t alignment;
};

struct native_layout {
    uintptr_t name;
    uintptr_t first;
    uintptr_t count;
    uintptr_t size;
    uintptr_t alignment;
};

struct native_layout_context {
    struct psl_parser *parser;
    const uint8_t *source;
    struct native_layout *layouts;
    uintptr_t layout_count;
    uintptr_t layout_capacity;
    struct native_layout_field *fields;
    uintptr_t field_count;
    uintptr_t field_capacity;
    struct native_type_shape *scratch;
    uint32_t error;
};

extern uintptr_t parser_next(struct psl_parser *parser);
extern int native_layout_form_p(struct native_layout_context *context,
                                uintptr_t root);
extern int native_register_layout(struct native_layout_context *context,
                                   uintptr_t root);
extern int native_resolve_type(struct native_layout_context *context,
                               uintptr_t type,
                               struct native_type_shape *output);

struct sample {
    uint8_t tag;
    uint8_t *data;
    uint32_t count;
};

struct outer {
    uint16_t head;
    struct sample inner;
    uint8_t tail;
};

struct node {
    struct sample *next;
};

static int check_layouts(void) {
    static const char source[] =
        "(defcstruct sample (tag u8) (data (ptr u8)) (count u32))\n"
        "(defcstruct outer (head u16) (inner sample) (tail u8))\n"
        "(defcstruct node (next (ptr sample)))\n";
    struct psl_ast_node nodes[128] = {0};
    struct native_layout layouts[8] = {0};
    struct native_layout_field fields[16] = {0};
    struct native_type_shape scratch = {0};
    struct psl_token token = {0};
    struct psl_scanner scanner = {
        (const uint8_t *)source, sizeof source - 1, 0, 0
    };
    struct psl_parser parser = {
        &scanner, &token, 0, nodes, 0, 128, 0
    };
    struct native_layout_context context = {
        &parser, (const uint8_t *)source, layouts, 0, 8,
        fields, 0, 16, &scratch, 0
    };

    for (int i = 0; i < 3; ++i) {
        uintptr_t root = parser_next(&parser);
        if (!root || !native_layout_form_p(&context, root) ||
            !native_register_layout(&context, root)) return 0;
    }
    if (parser_next(&parser) || parser.error || context.error ||
        context.layout_count != 3 || context.field_count != 7) return 0;
    if (layouts[0].size != sizeof(struct sample) ||
        layouts[0].alignment != _Alignof(struct sample) ||
        fields[0].offset != offsetof(struct sample, tag) ||
        fields[1].offset != offsetof(struct sample, data) ||
        fields[2].offset != offsetof(struct sample, count)) return 0;
    if (layouts[1].size != sizeof(struct outer) ||
        layouts[1].alignment != _Alignof(struct outer) ||
        fields[3].offset != offsetof(struct outer, head) ||
        fields[4].offset != offsetof(struct outer, inner) ||
        fields[5].offset != offsetof(struct outer, tail)) return 0;
    if (layouts[2].size != sizeof(struct node) ||
        layouts[2].alignment != _Alignof(struct node) ||
        !native_resolve_type(&context, fields[4].type_ast, &scratch) ||
        scratch.kind != 3 || scratch.size != sizeof(struct sample)) return 0;
    if (!native_resolve_type(&context, fields[1].type_ast, &scratch) ||
        scratch.kind != 2 || scratch.size != sizeof(void *)) return 0;
    return 1;
}

static int rejected(const char *source) {
    struct psl_ast_node nodes[64] = {0};
    struct native_layout layouts[4] = {0};
    struct native_layout_field fields[8] = {0};
    struct native_type_shape scratch = {0};
    struct psl_token token = {0};
    struct psl_scanner scanner = {
        (const uint8_t *)source, strlen(source), 0, 0
    };
    struct psl_parser parser = {
        &scanner, &token, 0, nodes, 0, 64, 0
    };
    struct native_layout_context context = {
        &parser, (const uint8_t *)source, layouts, 0, 4,
        fields, 0, 8, &scratch, 0
    };
    uintptr_t root = parser_next(&parser);
    return root && native_layout_form_p(&context, root) &&
           !native_register_layout(&context, root);
}

int main(void) {
    if (!check_layouts() ||
        !rejected("(defcstruct bad (x u8) (x u64))") ||
        !rejected("(defcstruct bad (x missing))") ||
        !rejected("(defcstruct bad (x (ptr missing)))") ||
        !rejected("(defcstruct bad (x (ptr u8 extra)))") ||
        !rejected("(defcstruct bad)") ||
        !rejected("(defcstruct bad x)")) {
        fputs("native structure layout mismatch\n", stderr);
        return 1;
    }
    return 0;
}
