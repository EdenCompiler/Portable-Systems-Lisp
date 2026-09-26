#ifndef PSL_BOOTSTRAP_NATIVE_API_H
#define PSL_BOOTSTRAP_NATIVE_API_H

#include <stdint.h>

/* Temporary C host boundary for the compiled PSL bootstrap modules. */
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

struct psl_parsed_integer {
    uint64_t magnitude;
    uint8_t negative;
    uint8_t radix;
};

struct native_function {
    const uint8_t *name;
    uintptr_t name_length;
    uintptr_t offset;
    uintptr_t size;
    uintptr_t arity;
    uintptr_t exported;
};

struct native_hir_node {
    uint32_t kind;
    uint32_t type_code;
    uint64_t value;
    uintptr_t left;
    uintptr_t right;
    uintptr_t target;
    uintptr_t source;
    uint32_t scalar_code;
    uintptr_t pointee;
};

struct native_hir_arena {
    struct native_hir_node *nodes;
    uintptr_t count;
    uintptr_t capacity;
    uint32_t error;
};

struct native_call_fixup {
    uintptr_t instruction;
    uintptr_t target;
};

struct native_fixup_arena {
    struct native_call_fixup *items;
    uintptr_t count;
    uintptr_t capacity;
    uint32_t error;
};

struct native_ir_type {
    uint32_t kind, scalar_code;
    uintptr_t pointee, left, right;
};
struct native_ssa_value {
    uint32_t kind, scalar_code;
    uintptr_t pointee;
    uint64_t value;
    uintptr_t left, right, target, source, block, next;
    uintptr_t predecessor_left, predecessor_right;
};
struct native_ssa_block {
    uintptr_t first, last;
    uint32_t terminator;
    uintptr_t condition, target_left, target_right, result;
    uint8_t visit;
};
struct native_ssa_arena {
    struct native_ssa_value *values;
    struct native_ir_type *types;
    uintptr_t value_count, value_capacity;
    struct native_ssa_block *blocks;
    uintptr_t block_count, block_capacity, current;
    uint32_t error;
};

struct native_lir_instruction {
    uint32_t kind, scalar_code;
    uintptr_t pointee;
    uint64_t value;
    uintptr_t left, right, target, source, destination;
};
struct native_lir_block {
    uintptr_t first, last;
    uint8_t visit;
};
struct native_lir_arena {
    struct native_lir_instruction *instructions;
    uintptr_t count, capacity;
    struct native_ir_type *types;
    uintptr_t value_count, value_capacity;
    struct native_lir_block *blocks;
    uintptr_t label_count, label_capacity;
    uint32_t error;
};

struct native_compile_context {
    struct psl_parser *parser;
    const uint8_t *source;
    struct psl_parsed_integer *integer;
    struct native_hir_arena *hir;
    struct byte_buffer *code;
    struct native_fixup_arena *fixups;
    struct native_function *functions;
    struct native_signature_context *signatures;
    uintptr_t prior_count;
    uintptr_t current_arity;
    struct native_signature *current_signature;
    uint32_t expected_type;
    uintptr_t active_binding;
    uintptr_t local_count;
    uintptr_t expected_pointee;
    struct native_ssa_arena *ssa;
    uintptr_t *bindings;
    struct native_lir_arena *lir;
    uintptr_t *labels;
    struct native_fixup_arena *jumps;
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

struct native_parameter {
    uintptr_t name;
    uintptr_t type_ast;
    uintptr_t size;
    uint32_t kind;
};

struct native_signature {
    uintptr_t name;
    uintptr_t first_parameter;
    uintptr_t arity;
    uintptr_t result_type;
    uintptr_t result_size;
    uint32_t result_kind;
    uintptr_t body;
    uint8_t exported;
};

struct native_signature_context {
    struct native_layout_context *layouts;
    struct native_signature *signatures;
    uintptr_t signature_count;
    uintptr_t signature_capacity;
    struct native_parameter *parameters;
    uintptr_t parameter_count;
    uintptr_t parameter_capacity;
    uint32_t error;
};

extern uintptr_t parser_next(struct psl_parser *parser);
extern uint32_t native_source_form_kind(struct psl_parser *, const uint8_t *, uintptr_t);
extern uintptr_t native_source_include_size(struct psl_parser *, const uint8_t *, uintptr_t);
extern int native_source_include_copy(struct psl_parser *, const uint8_t *, uintptr_t,
                                      uint8_t *, uintptr_t);
extern int predeclare_scalar_form(struct native_compile_context *context,
                                  struct native_signature *signature,
                                  struct native_function *function);
extern int compile_scalar_form(struct native_compile_context *context,
                               struct native_signature *signature,
                               struct native_function *function);
extern int write_elf64_functions(uint16_t machine, uint32_t flags,
                                  const uint8_t *code, uintptr_t code_size,
                                  const struct native_function *functions,
                                  uintptr_t count,
                                  struct byte_buffer *object);
extern int patch_call_fixups(struct byte_buffer *code,
                             const struct native_function *functions,
                             uintptr_t count,
                             struct native_fixup_arena *fixups);
extern int native_layout_form_p(struct native_layout_context *context,
                                uintptr_t root);
extern int native_register_layout(struct native_layout_context *context,
                                   uintptr_t root);
extern int native_parse_signature(struct native_signature_context *context,
                                   uintptr_t root);


extern int ssa_verify_function(struct native_compile_context *context);
extern int lir_verify_function(struct native_compile_context *context);
extern int hir_verify_root(struct native_hir_arena *arena, uintptr_t root,
                           const struct native_function *functions,
                           uintptr_t count, uintptr_t arity);
extern int hir_verify_scalar_tree(struct native_compile_context *context,
                                  uintptr_t root, uintptr_t depth);
#endif
