#include "../bootstrap/native_api.h"
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
int main(void) {
    const char *text = "(defmacro twice (&rest values) `(wrap+ ,@values)) "
        "(twice (wrap+ number 1) (wrap+ number 1)) "
        "(defmacro twice (&body values) `(twice ,@values)) (twice number)";
    struct native_ct_environment env = {.names=names, .name_capacity=sizeof names,
        .packages=packages, .package_capacity=16, .symbols=symbols, .symbol_capacity=2400,
        .present=present, .present_capacity=3000, .uses=uses, .use_capacity=32,
        .aliases=aliases, .alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner = {(const uint8_t *)text, strlen(text), 0, 0};
    struct psl_token token = {0};
    struct native_reader_environment reader = {.environment=&env, .identities=identities, .capacity=256};
    struct psl_parser parser = {.scanner=&scanner, .token=&token, .nodes=nodes, .capacity=256, .environment=&reader};
    struct psl_parsed_integer integer = {0};
    struct native_compile_context compiler = {.parser=&parser, .source=(const uint8_t *)text,
        .integer=&integer, .data_bytes=scratch, .data_byte_capacity=sizeof scratch};
    struct native_tree_context tree = {.parser=&parser, .reader=&reader, .limit=32};
    struct native_macro_definition definitions[1] = {{0}};
    struct native_macro_registry registry = {.parser=&parser, .source=(const uint8_t *)text, .tree=&tree,
        .definitions=definitions, .capacity=1};
    uintptr_t root = parser_next(&parser);
    assert(root && native_resolve_source_identities(&compiler, &reader));
    assert(native_macro_register(&registry, root) == 1);
    struct native_macro_binding bindings[1] = {{0}};
    struct native_macro_call call = {.registry=&registry, .bindings=bindings, .capacity=1, .step_limit=32};
    root = parser_next(&parser);
    assert(root && native_resolve_source_identities(&compiler, &reader));
    uintptr_t argument = nodes[nodes[root-1].first-1].next;
    uintptr_t count = parser.count;
    struct psl_ast_node original[256]; memcpy(original, nodes, sizeof original);
    reader.capacity = count + 2;
    struct native_macro_expansion result = {0};
    int status = native_macroexpand_1(&call, root, &result);
    assert(!status && call.error == 1);
    assert(parser.count == count && reader.count == count && !parser.error);
    assert(result.form == root && !result.expanded);
    assert(!memcmp(original, nodes, count * sizeof *nodes));
    reader.capacity = 256; call.error = 0; tree.error = 0;
    assert(native_macroexpand_1(&call, root, &result) && result.expanded);
    assert(result.form > count && parser.count == reader.count);
    assert(!memcmp(original, nodes, count * sizeof *nodes));
    uintptr_t head = nodes[result.form-1].first;
    uintptr_t plus = identities[nodes[argument-1].first-1].symbol;
    assert(plus && identities[head-1].symbol == plus);
    assert(identities[head-1].origin == root);
    uintptr_t first = nodes[head-1].next;
    uintptr_t second = nodes[first-1].next;
    assert(first && second && first != second && !nodes[second-1].next);
    assert(nodes[first-1].kind == 1 && nodes[second-1].kind == 1);
    assert(identities[first-1].origin == argument && identities[second-1].origin == nodes[argument-1].next);
    uintptr_t first_head = nodes[first-1].first;
    uintptr_t second_head = nodes[second-1].first;
    assert(identities[first_head-1].symbol == plus && identities[second_head-1].symbol == plus);
    uintptr_t number = identities[nodes[nodes[argument-1].first-1].next-1].symbol;
    assert(number && identities[nodes[first_head-1].next-1].symbol == number);
    assert(identities[nodes[second_head-1].next-1].symbol == number);
    assert(native_tree_verify(&tree, result.form));
    count = parser.count;
    uintptr_t expanded = result.form;
    assert(native_macroexpand_1(&call, expanded, &result));
    assert(result.form == expanded && !result.expanded && parser.count == count);
    uintptr_t last=nodes[expanded-1].last;
    uintptr_t next=nodes[last-1].next;
    nodes[last-1].next=last; tree.error=0;
    assert(!native_tree_copy(&tree, expanded) && tree.error==NATIVE_MACRO_REFERENCE);
    assert(parser.count==count && reader.count==count);
    nodes[last-1].next=next; tree.error=0;
    uintptr_t uid=identities[head-1].symbol;
    identities[head-1].symbol=env.symbol_count+1;
    assert(!native_tree_verify(&tree, expanded) && tree.error==NATIVE_MACRO_REFERENCE);
    identities[head-1].symbol=uid; tree.error=0;
    assert(!native_tree_verify(&tree, UINTPTR_MAX) && tree.error==NATIVE_MACRO_REFERENCE);
    tree.error=0;
    root=parser_next(&parser);
    assert(root && native_resolve_source_identities(&compiler, &reader));
    assert(native_macro_register(&registry, root)==1 && registry.count==1);
    root=parser_next(&parser);
    assert(root && native_resolve_source_identities(&compiler, &reader));
    count=parser.count;
    memcpy(original, nodes, count*sizeof *nodes);
    call.steps=0; call.step_limit=2;
    assert(!native_macroexpand(&call, root, &result));
    assert(call.error==NATIVE_MACRO_DEPTH && call.origin==root && !call.count);
    assert(result.form==root && !result.expanded);
    assert(parser.count==count && reader.count==count && !parser.error);
    assert(!memcmp(original, nodes, count*sizeof *nodes));
    assert(tree.origin==0);
    call.error=0; tree.error=0; parser.environment=NULL;
    assert(!native_tree_copy(&tree, expanded));
    parser.environment=&reader;
    puts("native macroexpand-1 clones templates, preserves caller identities and rolls back capacity failures");
}
