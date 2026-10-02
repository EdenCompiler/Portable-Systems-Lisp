#ifndef PSL_BOOTSTRAP_NATIVE_API_H
#define PSL_BOOTSTRAP_NATIVE_API_H

#include <stdint.h>
#include <stddef.h>
#include "frontend/environment.h"

/* Temporary C host boundary for the compiled PSL bootstrap modules. */
struct byte_buffer {
    uint8_t *data;
    uintptr_t length;
    uintptr_t capacity;
};

struct native_data_symbol {
    const uint8_t *name;
    uintptr_t name_length;
    const uint8_t *bytes;
    uintptr_t size;
    uintptr_t alignment;
    uint8_t exported;
};

extern int write_elf64_data(uint16_t machine, uint32_t flags,
                            const struct native_data_symbol *, uintptr_t,
                            struct byte_buffer *);
extern int write_coff64_data(const struct native_data_symbol *, uintptr_t,
                             struct byte_buffer *);

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
    struct native_reader_environment *environment;
};

struct psl_parsed_integer {
    uint64_t magnitude;
    uint8_t negative;
    uint8_t radix;
};

/* Caller-owned decimal conversion scratch, independent of target ABI. */
struct native_float_uint {
    uint32_t *words;
    uintptr_t count, capacity;
};
struct native_float_parser {
    struct native_float_uint numerator, denominator;
    uintptr_t digits, fractional, discarded;
    int64_t exponent;
    uint32_t code;
    uint8_t negative, sticky, saw_digit, saw_point, saw_marker;
    int32_t status;
    uintptr_t cursor;
};
extern int parse_float_token(const uint8_t *, uintptr_t, uintptr_t,
                             struct native_float_parser *, uint32_t *, uint32_t *,
                             uintptr_t, struct psl_parsed_integer *);

struct native_function {
    const uint8_t *name;
    uintptr_t name_length;
    uintptr_t offset;
    uintptr_t size;
    uintptr_t arity;
    uintptr_t exported;
    uintptr_t imported;
    uintptr_t referenced;
    uintptr_t frame_size;
    uintptr_t prologue_size;
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
    uintptr_t allocation_region;
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
    int32_t live;
    uintptr_t remap;
};
struct native_ssa_block {
    uintptr_t first, last;
    uint32_t terminator;
    uintptr_t condition, target_left, target_right, result;
    uint8_t visit;
    uintptr_t remap;
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
    uint32_t optimization;
    uintptr_t fold_cursor;
    int32_t fold_changed;
    int32_t effects_changed;
    struct native_ssa_value *inline_values;
    uintptr_t inline_count, inline_capacity, inline_cursor;
    uint32_t target;
    uintptr_t backend_frame_size, backend_outgoing_size, backend_prologue_size;
    struct native_data_import *data_imports;
    uintptr_t data_count, data_capacity;
    uint8_t *data_bytes;
    uintptr_t data_byte_count, data_byte_capacity;
    struct native_fixup_arena *data_fixups;
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
    uint32_t target;
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
    uint8_t imported;
    uint8_t allocation_free, effect_ready;
    uintptr_t inline_base, inline_count, inline_result;
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

struct native_data_import {
    const uint8_t *name;
    uintptr_t name_length;
    uintptr_t type_ast;
    uintptr_t size;
    uintptr_t alignment;
    const uint8_t *bytes;
    uint64_t initial;
    uint8_t defined;
    uint8_t global;
    uint8_t referenced;
};

struct native_storage {
    struct psl_ast_node *syntax;
    struct native_layout *layouts;
    struct native_layout_field *fields;
    struct native_parameter *parameters;
    struct native_function *functions;
    struct native_signature *signatures;
    struct native_data_import *data_imports;
    uint8_t *data_bytes;
    struct native_hir_node *hir;
    struct native_ssa_value *ssa;
    struct native_ssa_block *ssa_blocks;
    struct native_ir_type *types;
    struct native_lir_instruction *lir;
    struct native_lir_block *lir_blocks;
    struct native_call_fixup *calls, *jumps, *data_fixups;
    uintptr_t *bindings, *labels;
    uint8_t *code, *object;
    struct native_ssa_value *inline_values;
    uint8_t *symbol_names;
    struct native_ct_package *packages;
    struct native_ct_symbol *symbols;
    struct native_ct_presence *present;
    struct native_ct_use *uses;
    struct native_ct_alias *aliases;
    struct native_source_identity *identities;
    uintptr_t *buckets;
};

struct native_driver {
    uint8_t *source;
    size_t length;
    struct native_storage storage;
    struct psl_scanner scanner;
    struct psl_token token;
    struct psl_parser parser;
    struct psl_parsed_integer integer;
    struct native_type_shape shape;
    struct native_layout_context layouts;
    struct native_signature_context signature_context;
    struct native_hir_arena hir;
    struct native_ssa_arena ssa;
    struct native_lir_arena lir;
    struct native_fixup_arena calls, jumps, data_fixups;
    struct byte_buffer code, object;
    struct native_compile_context context;
    struct native_ct_environment environment;
    struct native_reader_environment reader;
};

/* A zeroed driver takes ownership of a free-compatible SOURCE buffer. Prepare
   allocates/initializes its arenas; release handles partial failure and repeated
   release. Release before preparing again; contexts are invalid after release. */
extern int native_prepare_driver(struct native_driver *);
extern int native_release_driver(struct native_driver *);

/* Zero means success. Form is a one-based AST reference; index is a
   zero-based signature index. Only the failing phase's location is valid. */
enum native_unit_phase {
    NATIVE_UNIT_LAYOUT = 1,
    NATIVE_UNIT_IMPORT,
    NATIVE_UNIT_SIGNATURE,
    NATIVE_UNIT_COLLECTION,
    NATIVE_UNIT_PREDECLARE,
    NATIVE_UNIT_BODY,
    NATIVE_UNIT_CALL_FIXUPS,
    NATIVE_UNIT_OBJECT,
    NATIVE_UNIT_ALLOCATION_EFFECT,
    NATIVE_UNIT_TARGET
};
struct native_unit_result {
    uintptr_t phase, form, index;
};

/* Native subset CLI: [-O0|-O1] SOURCE.lisp OUTPUT.o. Status: 0 success, 1 rejected
   source, 2 usage/host/allocation failure. Run calls may be repeated. */
extern int native_compiler_main(int argc, char **argv);
extern int native_run_compiler(const char *source_path, const char *output_path);
extern int native_run_compiler_options(const char *source_path, const char *output_path,
                                        uint32_t optimization);

/* Fresh contexts/arenas and live caller-owned buffers are required. */
extern int native_compile_unit(struct native_compile_context *, struct byte_buffer *,
                               struct native_unit_result *);

extern uintptr_t parser_next(struct psl_parser *parser);
extern uint32_t native_source_form_kind(struct psl_parser *, const uint8_t *, uintptr_t);
extern uintptr_t native_source_include_size(struct psl_parser *, const uint8_t *, uintptr_t);
extern int native_source_include_copy(struct psl_parser *, const uint8_t *, uintptr_t,
                                      uint8_t *, uintptr_t);
extern uintptr_t native_source_ffi_size(struct psl_parser *, const uint8_t *, uintptr_t);
extern int native_source_ffi_copy(struct psl_parser *, const uint8_t *, uintptr_t,
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
extern int native_import_form_p(struct native_signature_context *, uintptr_t);
extern int native_resolve_source_identities(struct native_compile_context *,
                                            struct native_reader_environment *);
extern int native_parse_import(struct native_signature_context *, uintptr_t);
extern int write_elf64_calls(const uint8_t *, uintptr_t, const struct native_function *,
                             uintptr_t, const struct native_fixup_arena *, struct byte_buffer *);
extern int write_coff64_calls(const uint8_t *, uintptr_t, const struct native_function *,
                              uintptr_t, const struct native_fixup_arena *, struct byte_buffer *);
extern int native_parse_signature(struct native_signature_context *context,
                                   uintptr_t root);


extern int ssa_optimize_function(struct native_compile_context *context);
/* Native output targets, independent of the architecture hosting the compiler. */
enum native_target_id { NATIVE_TARGET_X86_64_LINUX = 0, NATIVE_TARGET_AARCH64_LINUX = 1,
                        NATIVE_TARGET_RISCV64_LINUX = 2, NATIVE_TARGET_X86_64_WINDOWS = 3 };
extern int native_run_compiler_target(const char *source, const char *output,
                                      uint32_t optimization, uint32_t target);
extern int write_elf64_calls_target(uint32_t target, const uint8_t *code, uintptr_t code_size,
                                  const struct native_function *functions, uintptr_t count,
                                  struct native_fixup_arena *fixups, struct byte_buffer *buffer);
extern int write_elf64_calls_data_target(
    uint32_t target, const uint8_t *code, uintptr_t code_size,
    const struct native_function *functions, uintptr_t function_count,
    struct native_fixup_arena *calls, const struct native_data_import *imports,
    uintptr_t import_count, struct native_fixup_arena *data_fixups,
    struct byte_buffer *buffer);
extern int write_elf64_calls_data(
    const uint8_t *code, uintptr_t code_size,
    const struct native_function *functions, uintptr_t function_count,
    struct native_fixup_arena *calls, const struct native_data_import *imports,
    uintptr_t import_count, struct native_fixup_arena *data_fixups,
    struct byte_buffer *buffer);
extern int write_coff64_calls_data(
    const uint8_t *code, uintptr_t code_size,
    const struct native_function *functions, uintptr_t function_count,
    struct native_fixup_arena *calls, const struct native_data_import *imports,
    uintptr_t import_count, struct native_fixup_arena *data_fixups,
    struct byte_buffer *buffer);
extern int hir_verify_region_metadata(struct native_compile_context *context, uintptr_t index);
extern int ssa_verify_liveness(struct native_compile_context *context);
extern int ssa_verify_function(struct native_compile_context *context);
extern int lir_verify_function(struct native_compile_context *context);
extern int hir_verify_root(struct native_hir_arena *arena, uintptr_t root,
                           const struct native_function *functions,
                           uintptr_t count, uintptr_t arity);
extern int hir_verify_scalar_tree(struct native_compile_context *context,
                                  uintptr_t root, uintptr_t depth);
#endif
