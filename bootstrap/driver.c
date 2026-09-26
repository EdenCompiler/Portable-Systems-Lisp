#include "native_api.h"
#include "host/source.h"
#include <stdio.h>
#include <stdlib.h>

static int write_object(const char *path, const struct byte_buffer *object) {
    FILE *stream = fopen(path, "wb");
    int result;

    if (!stream) return 0;
    result = fwrite(object->data, 1, object->length, stream) == object->length;
    if (fclose(stream) != 0) result = 0;
    return result;
}

static int collect_forms(struct psl_parser *parser,
                         struct native_layout_context *layouts,
                         struct native_signature_context *signatures) {
    uintptr_t root;

    while ((root = parser_next(parser)) != 0) {
        if (native_layout_form_p(layouts, root)) {
            if (!native_register_layout(layouts, root)) {
                fprintf(stderr, "cannot register layout at byte %lu\n",
                         (unsigned long)parser->nodes[root - 1].start);
                return 0;
            }
            continue;
        }
        if (!native_parse_signature(signatures, root)) {
            fprintf(stderr, "cannot parse declaration at byte %lu\n",
                     (unsigned long)parser->nodes[root - 1].start);
            return 0;
        }
    }
    return parser->error == 0 && layouts->error == 0 &&
           signatures->signature_count != 0;
}

static int predeclare_forms(struct native_compile_context *context,
                            uintptr_t count) {
    for (uintptr_t i = 0; i < count; ++i) {
        if (!predeclare_scalar_form(context,
                                    &context->signatures->signatures[i],
                                    &context->functions[i])) {
            fprintf(stderr, "cannot predeclare function at byte %lu\n",
                     (unsigned long)context->parser->nodes[
                       context->signatures->signatures[i].name - 1].start);
            return 0;
        }
    }
    return 1;
}

static int compile_forms(struct native_compile_context *context,
                         uintptr_t count) {
    context->prior_count = count;
    for (uintptr_t i = 0; i < count; ++i) {
        if (!compile_scalar_form(context,
                                 &context->signatures->signatures[i],
                                 &context->functions[i])) {
            struct native_function *function = &context->functions[i];
            fprintf(stderr, "cannot compile function: %.*s\n",
                     (int)function->name_length, function->name);
            return 0;
        }
    }
    return 1;
}

struct native_storage {
    struct psl_ast_node *syntax;
    struct native_layout *layouts;
    struct native_layout_field *fields;
    struct native_parameter *parameters;
    struct native_function *functions;
    struct native_signature *signatures;
    struct native_hir_node *hir;
    struct native_ssa_value *ssa;
    struct native_ssa_block *ssa_blocks;
    struct native_ir_type *types;
    struct native_lir_instruction *lir;
    struct native_lir_block *lir_blocks;
    struct native_call_fixup *calls, *jumps;
    uintptr_t *bindings, *labels;
    uint8_t *code, *object;
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
    struct native_fixup_arena calls, jumps;
    struct byte_buffer code, object;
    struct native_compile_context context;
};

static int allocate_frontend(struct native_storage *s, size_t capacity) {
    s->syntax = calloc(capacity, sizeof *s->syntax);
    s->layouts = calloc(capacity, sizeof *s->layouts);
    s->fields = calloc(capacity, sizeof *s->fields);
    s->parameters = calloc(capacity, sizeof *s->parameters);
    s->functions = calloc(capacity, sizeof *s->functions);
    s->signatures = calloc(capacity, sizeof *s->signatures);
    return s->syntax && s->layouts && s->fields && s->parameters &&
           s->functions && s->signatures;
}

static int allocate_ir(struct native_storage *s, size_t capacity) {
    s->hir = calloc(capacity, sizeof *s->hir);
    s->ssa = calloc(capacity, sizeof *s->ssa);
    s->ssa_blocks = calloc(capacity, sizeof *s->ssa_blocks);
    s->types = calloc(capacity, sizeof *s->types);
    s->bindings = calloc(capacity, sizeof *s->bindings);
    s->lir = calloc(6 * capacity, sizeof *s->lir);
    s->lir_blocks = calloc(3 * capacity, sizeof *s->lir_blocks);
    return s->hir && s->ssa && s->ssa_blocks && s->types &&
           s->bindings && s->lir && s->lir_blocks;
}

static int allocate_output(struct native_storage *s, size_t capacity) {
    s->calls = calloc(capacity, sizeof *s->calls);
    s->jumps = calloc(3 * capacity, sizeof *s->jumps);
    s->labels = calloc(3 * capacity, sizeof *s->labels);
    s->code = calloc(1048576, 1);
    s->object = calloc(1200000, 1);
    return s->calls && s->jumps && s->labels && s->code && s->object;
}

static void release_driver(struct native_driver *d) {
    struct native_storage *s = &d->storage;
    free(s->syntax);
    free(s->layouts);
    free(s->fields);
    free(s->parameters);
    free(s->functions);
    free(s->signatures);
    free(s->hir);
    free(s->ssa);
    free(s->ssa_blocks);
    free(s->types);
    free(s->bindings);
    free(s->lir);
    free(s->lir_blocks);
    free(s->calls);
    free(s->jumps);
    free(s->labels);
    free(s->code);
    free(s->object);
    free(d->source);
}

static void initialize_frontend(struct native_driver *d) {
    struct native_storage *s = &d->storage;
    size_t capacity = d->length + 1;
    d->scanner = (struct psl_scanner){d->source, d->length, 0, 0};
    d->parser = (struct psl_parser){&d->scanner, &d->token, 0, s->syntax, 0, capacity, 0};
    d->layouts = (struct native_layout_context){
        &d->parser, d->source, s->layouts, 0, capacity,
        s->fields, 0, capacity, &d->shape, 0
    };
    d->signature_context = (struct native_signature_context){
        &d->layouts, s->signatures, 0, capacity, s->parameters, 0, capacity, 0
    };
}

static void initialize_ir(struct native_driver *d) {
    struct native_storage *s = &d->storage;
    size_t capacity = d->length + 1;
    d->hir = (struct native_hir_arena){s->hir, 0, capacity, 0};
    d->ssa = (struct native_ssa_arena){s->ssa, s->types, 0, capacity, s->ssa_blocks, 0, capacity, 0, 0};
    d->lir = (struct native_lir_arena){s->lir, 0, 6 * capacity, s->types, 0, capacity, s->lir_blocks, 0, 3 * capacity, 0};
}

static void initialize_output(struct native_driver *d) {
    struct native_storage *s = &d->storage;
    size_t capacity = d->length + 1;
    d->calls = (struct native_fixup_arena){s->calls, 0, capacity, 0};
    d->jumps = (struct native_fixup_arena){s->jumps, 0, 3 * capacity, 0};
    d->code = (struct byte_buffer){s->code, 0, 1048576};
    d->object = (struct byte_buffer){s->object, 0, 1200000};
    d->context = (struct native_compile_context){
        .parser = &d->parser, .source = d->source, .integer = &d->integer,
        .hir = &d->hir, .code = &d->code, .fixups = &d->calls,
        .functions = s->functions, .signatures = &d->signature_context,
        .ssa = &d->ssa, .bindings = s->bindings, .lir = &d->lir,
        .labels = s->labels, .jumps = &d->jumps
    };
}

static int prepare_driver(struct native_driver *d) {
    size_t capacity = d->length + 1;
    if (!allocate_frontend(&d->storage, capacity) ||
        !allocate_ir(&d->storage, capacity) ||
        !allocate_output(&d->storage, capacity)) return 0;
    initialize_frontend(d);
    initialize_ir(d);
    initialize_output(d);
    return 1;
}

static int compile_unit(struct native_driver *d) {
    return collect_forms(&d->parser, &d->layouts, &d->signature_context) &&
           predeclare_forms(&d->context, d->signature_context.signature_count) &&
           compile_forms(&d->context, d->signature_context.signature_count) &&
           patch_call_fixups(&d->code, d->storage.functions,
                             d->signature_context.signature_count, &d->calls) &&
           write_elf64_functions(62, 0, d->code.data, d->code.length,
                                 d->storage.functions, d->signature_context.signature_count,
                                 &d->object);
}

static int run_compiler(const char *source_path, const char *output_path) {
    struct native_driver driver = {0};
    int result = 0;
    driver.source = native_read_source_unit(source_path, &driver.length);
    if (!driver.source) {
        fprintf(stderr, "cannot read source: %s\n", source_path);
        return 2;
    }
    if (!prepare_driver(&driver)) {
        fprintf(stderr, "cannot allocate compiler buffers\n");
        result = 2;
    } else if (!compile_unit(&driver)) {
        fprintf(stderr, "unsupported or malformed source: %s\n", source_path);
        result = 1;
    } else if (!write_object(output_path, &driver.object)) {
        fprintf(stderr, "cannot write object: %s\n", output_path);
        result = 2;
    }
    release_driver(&driver);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: pslcc-native-slice SOURCE.lisp OUTPUT.o\n");
        return 2;
    }
    return run_compiler(argv[1], argv[2]);
}
