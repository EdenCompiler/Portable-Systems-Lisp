#include "../bootstrap/native_api.h"
#include "harness_bootstrap_macro_registry.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint8_t names[200000], scratch[4096];
static struct native_ct_package packages[16];
static struct native_ct_symbol symbols[2400];
static struct native_ct_presence present[3000];
static struct native_ct_use uses[32];
static struct native_ct_alias aliases[8];
static struct native_source_identity identities[256];
static struct psl_ast_node nodes[256];

static uintptr_t next_form(struct psl_parser *parser,
                           struct native_compile_context *compiler,
                           struct native_reader_environment *reader) {
    uintptr_t root = parser_next(parser);
    assert(root && native_resolve_source_identities(compiler, reader));
    return root;
}

int main(void) {
    const char *text =
        "(defmacro pair ((left right)) (list 'wrap+ left right)) "
        "(pair (1 2)) (pair (1 2)) (pair (1))";
    struct native_ct_environment env = {.names=names, .name_capacity=sizeof names,
        .packages=packages, .package_capacity=16, .symbols=symbols, .symbol_capacity=2400,
        .present=present, .present_capacity=3000, .uses=uses, .use_capacity=32,
        .aliases=aliases, .alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner = {(const uint8_t *)text, strlen(text), 0, 0};
    struct psl_token token = {0};
    struct native_reader_environment reader = {.environment=&env, .identities=identities,
                                                .capacity=256};
    struct psl_parser parser = {.scanner=&scanner, .token=&token, .nodes=nodes,
                                .capacity=256, .environment=&reader};
    struct psl_parsed_integer integer = {0};
    struct native_compile_context compiler = {.parser=&parser, .source=(const uint8_t *)text,
        .integer=&integer, .data_bytes=scratch, .data_byte_capacity=sizeof scratch};
    struct native_tree_context tree = {.parser=&parser, .reader=&reader, .limit=32};
    uintptr_t definition_handle = macro_test_open_definition_handle(1);
    struct native_macro_registry registry = {.parser=&parser, .source=(const uint8_t *)text,
        .tree=&tree, .definition_handle=definition_handle, .capacity=1};
    uintptr_t definition = next_form(&parser, &compiler, &reader);
    assert(native_macro_register(&registry, definition) == 1);
    uintptr_t binding_handle = psl_rt_value_handle_open();
    struct native_macro_call call = {.registry=&registry, .binding_handle=binding_handle,
                                     .capacity=4, .step_limit=32};
    struct native_macro_expansion result = {0};
    uintptr_t valid = next_form(&parser, &compiler, &reader);
    uintptr_t before_count = parser.count;
    struct psl_ast_node before[256];
    memcpy(before, nodes, before_count * sizeof *nodes);
    assert(native_macroexpand_1(&call, valid, &result) && result.expanded);
    assert(parser.count == reader.count && native_tree_verify(&tree, result.form));
    assert(!memcmp(before, nodes, before_count * sizeof *nodes));

    uintptr_t capacity_form = next_form(&parser, &compiler, &reader);
    before_count = parser.count;
    memcpy(before, nodes, before_count * sizeof *nodes);
    call.capacity = 1;
    call.error = 0;
    tree.error = 0;
    assert(!native_macroexpand_1(&call, capacity_form, &result));
    assert(call.error == NATIVE_MACRO_CAPACITY && !call.count);
    assert(parser.count == before_count && reader.count == before_count);
    assert(!memcmp(before, nodes, before_count * sizeof *nodes));

    uintptr_t arity_form = next_form(&parser, &compiler, &reader);
    before_count = parser.count;
    memcpy(before, nodes, before_count * sizeof *nodes);
    call.capacity = 4;
    call.error = 0;
    tree.error = 0;
    assert(!native_macroexpand_1(&call, arity_form, &result));
    assert(call.error == NATIVE_MACRO_ARITY && !call.count);
    assert(parser.count == before_count && reader.count == before_count);
    assert(!memcmp(before, nodes, before_count * sizeof *nodes));
    psl_rt_value_handle_close(binding_handle);
    macro_test_close_definition_handle(definition_handle);
    assert(psl_rt_live_value_handles() == 0);
    puts("nested macro API preserves syntax and rolls back partial bindings on capacity and arity errors");
    return 0;
}
