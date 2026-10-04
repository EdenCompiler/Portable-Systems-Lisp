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
    const char *text="(defmacro choose (x &optional (y 3 supplied)) (list 'wrap+ x y)) (choose number) (choose number 7) (choose number 7 8) (defmacro fail (x) (list 1 unknown_control)) (fail number) (defmacro deep () (list (list (list (list (quote 42)))))) (deep)";
    struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,
        .symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,
        .aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner={(const uint8_t *)text,strlen(text),0,0};
    struct psl_token token={0};
    struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=256};
    struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=256,.environment=&reader};
    struct psl_parsed_integer integer={0};
    struct native_compile_context compiler={.parser=&parser,.source=(const uint8_t *)text,.integer=&integer,
        .data_bytes=scratch,.data_byte_capacity=sizeof scratch};
    struct native_tree_context tree={.parser=&parser,.reader=&reader,.limit=32};
    struct native_macro_definition definitions[3]={{0}};
    struct native_macro_registry registry={.parser=&parser,.source=(const uint8_t *)text,.tree=&tree,.definitions=definitions,.capacity=3};
    uintptr_t definition=parser_next(&parser);
    assert(definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,definition)==1);
    struct native_macro_binding bindings[3]={{0}};
    struct native_macro_call call={.registry=&registry,.bindings=bindings,.capacity=3,.step_limit=32};
    struct native_macro_expansion result={0};
    for (unsigned supplied=0;supplied<2;++supplied) {
        uintptr_t form=parser_next(&parser);
        assert(form && native_resolve_source_identities(&compiler,&reader));
        uintptr_t count=parser.count;
        struct psl_ast_node before[256]; memcpy(before,nodes,count*sizeof *nodes);
        assert(native_macroexpand_1(&call,form,&result) && result.expanded);
        assert(!memcmp(before,nodes,count*sizeof *nodes));
        assert(nodes[result.form-1].kind==1 && identities[result.form-1].origin==form);
        uintptr_t head=nodes[result.form-1].first;
        uintptr_t package=native_ct_find_package(&env,(const uint8_t *)"PSL",3);
        uintptr_t symbol=native_ct_find_symbol(&env,package,(const uint8_t *)"WRAP+",5);
        assert(symbol && identities[head-1].symbol==symbol && identities[head-1].origin==form);
        uintptr_t argument=nodes[nodes[form-1].first-1].next;
        uintptr_t value=nodes[head-1].next;
        assert(value && identities[value-1].symbol==identities[argument-1].symbol);
        assert(identities[value-1].origin==argument && nodes[value-1].start==nodes[argument-1].start);
        uintptr_t extra=nodes[value-1].next;
        assert(extra && !nodes[extra-1].next);
        if (supplied) {
            argument=nodes[argument-1].next;
            assert(identities[extra-1].origin==argument && nodes[extra-1].start==nodes[argument-1].start);
        } else {
            assert(identities[extra-1].origin==form && text[nodes[extra-1].start]=='3');
        }
        assert(native_tree_verify(&tree,result.form));
    }
    uintptr_t saved_count=parser.count;
    call.capacity=2; call.error=0; tree.error=0;
    /* Re-expanding the last valid call cannot publish an incomplete set of
       required/optional/supplied bindings. */
    assert(!native_macroexpand_1(&call,call.origin,&result));
    assert(call.error==NATIVE_MACRO_CAPACITY && !call.count);
    assert(parser.count==saved_count && reader.count==saved_count);
    call.capacity=3; call.error=0; tree.error=0;
    uintptr_t saved_capacity=parser.capacity;
    parser.capacity=saved_count+2;
    assert(!native_macroexpand_1(&call,call.origin,&result));
    assert(call.error==NATIVE_MACRO_CAPACITY && !call.count);
    assert(parser.count==saved_count && reader.count==saved_count && !parser.error);
    parser.capacity=saved_capacity; call.error=0; tree.error=0;

    uintptr_t form=parser_next(&parser);
    assert(form && native_resolve_source_identities(&compiler,&reader));
    uintptr_t count=parser.count;
    assert(!native_macroexpand_1(&call,form,&result) && call.error==NATIVE_MACRO_ARITY);
    assert(parser.count==count && reader.count==count && !call.count);
    call.error=0; tree.error=0;
    definition=parser_next(&parser);
    assert(definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,definition)==2);
    form=parser_next(&parser);
    assert(form && native_resolve_source_identities(&compiler,&reader));
    count=parser.count;
    assert(!native_macroexpand_1(&call,form,&result) && call.error==NATIVE_MACRO_REFERENCE);
    assert(parser.count==count && reader.count==count && !call.count && !tree.depth);
    call.error=0; tree.error=0;
    definition=parser_next(&parser);
    assert(definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,definition)==3);
    form=parser_next(&parser);
    assert(form && native_resolve_source_identities(&compiler,&reader));
    count=parser.count; tree.limit=5;
    assert(!native_macroexpand_1(&call,form,&result) && call.error==NATIVE_MACRO_DEPTH);
    assert(parser.count==count && reader.count==count && !call.count && !tree.depth);
    tree.limit=32; tree.error=0; call.error=0;
    assert(native_macroexpand_1(&call,form,&result) && result.expanded);
    assert(native_tree_verify(&tree,result.form));
    puts("macro LIST API preserves caller syntax and rolls back partial construction, bindings, arity, evaluation and depth failures");

}
