#include "../bootstrap/native_api.h"
#include "../runtime/psl_runtime.h"
#include "harness_bootstrap_macro_registry.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static uint8_t names[200000],scratch[4096];
static struct native_ct_package packages[16];
static struct native_ct_symbol symbols[2400];
static struct native_ct_presence present[3000];
static struct native_ct_use uses[32];
static struct native_ct_alias aliases[8];
static struct native_source_identity identities[24000];
static struct psl_ast_node nodes[24000];
static uintptr_t next_form(struct psl_parser *parser,struct native_compile_context *compiler,struct native_reader_environment *reader) {
    uintptr_t form=parser_next(parser);
    assert(form && native_resolve_source_identities(compiler,reader));
    return form;
}
static void rejected(struct native_macro_call *call,uintptr_t form,struct native_macro_expansion *result,uint32_t error) {
    struct psl_parser *parser=call->registry->parser;
    uintptr_t count=parser->count;
    assert(!native_macroexpand_1(call,form,result));
    assert(call->error==error && !call->count && !call->registry->tree->depth);
    assert(parser->count==count && parser->environment->count==count);
    assert(result->form==form && !result->expanded);
    call->error=0; call->registry->tree->error=0;
}
static void explicit_nil_default_identity(void) {
    const char *source="(defmacro nil_default (&key ((:value value) nil)) value) (nil_default) (nil_default :value nil)";
    memset(names,0,sizeof names); memset(packages,0,sizeof packages); memset(symbols,0,sizeof symbols);
    memset(present,0,sizeof present); memset(uses,0,sizeof uses); memset(aliases,0,sizeof aliases);
    memset(identities,0,sizeof identities); memset(nodes,0,sizeof nodes); memset(scratch,0,sizeof scratch);
    struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,
        .symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,
        .aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner={(const uint8_t *)source,strlen(source),0,0};
    struct psl_token token={0};
    struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=24000};
    struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=24000,.environment=&reader};
    struct psl_parsed_integer integer={0};
    struct native_compile_context compiler={.parser=&parser,.source=(const uint8_t *)source,.integer=&integer,
        .data_bytes=scratch,.data_byte_capacity=sizeof scratch};
    struct native_tree_context tree={.parser=&parser,.reader=&reader,.limit=32};
    uintptr_t definition_handle=macro_test_open_definition_handle(1);
    struct native_macro_registry registry={.parser=&parser,.source=(const uint8_t *)source,.tree=&tree,.definition_handle=definition_handle,.capacity=1};
    uintptr_t definition=next_form(&parser,&compiler,&reader);
    assert(native_macro_register(&registry,definition)==1);
    uintptr_t binding_handle=psl_rt_value_handle_open();
    struct native_macro_call call={.registry=&registry,.binding_handle=binding_handle,.capacity=0,.step_limit=32};
    struct native_macro_expansion result={0};
    uintptr_t omitted=next_form(&parser,&compiler,&reader),count=parser.count;
    struct psl_ast_node before[64]; assert(count<=64); memcpy(before,nodes,count*sizeof *nodes);
    assert(!native_macroexpand_1(&call,omitted,&result));
    assert(call.error==NATIVE_MACRO_CAPACITY && !call.count && !tree.depth);
    assert(parser.count==count && reader.count==count && !memcmp(before,nodes,count*sizeof *nodes));
    assert(psl_rt_value_handle_get(binding_handle)==PSL_NIL);
    call.capacity=1; call.error=0; tree.error=0;
    assert(native_macroexpand_1(&call,omitted,&result) && result.expanded);
    assert(identities[result.form-1].symbol==env.nil_symbol && identities[result.form-1].origin==omitted);
    assert(native_tree_verify(&tree,result.form));
    uintptr_t supplied=next_form(&parser,&compiler,&reader);
    uintptr_t head=nodes[supplied-1].first;
    uintptr_t argument=nodes[head-1].next;
    argument=nodes[argument-1].next;
    assert(native_macroexpand_1(&call,supplied,&result) && result.expanded);
    assert(identities[result.form-1].symbol==env.nil_symbol && identities[result.form-1].origin==argument);
    assert(native_tree_verify(&tree,result.form));
    psl_rt_value_handle_close(binding_handle);
    macro_test_close_definition_handle(definition_handle);
    assert(psl_rt_live_value_handles()==0);
}
static void null_reader_nil_key_rejects_safely(void) {
    memset(names,0,sizeof names); memset(packages,0,sizeof packages); memset(symbols,0,sizeof symbols);
    memset(present,0,sizeof present); memset(uses,0,sizeof uses); memset(aliases,0,sizeof aliases);
    memset(identities,0,sizeof identities); memset(nodes,0,sizeof nodes); memset(scratch,0,sizeof scratch);
    const char *source="(defmacro nil_key (&key ((nil value) 3)) value) (nil_key ())";
    struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,
        .symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,
        .aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner={(const uint8_t *)source,strlen(source),0,0};
    struct psl_token token={0};
    struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=24000};
    struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=24000,.environment=&reader};
    struct psl_parsed_integer integer={0};
    struct native_compile_context compiler={.parser=&parser,.source=(const uint8_t *)source,.integer=&integer,
        .data_bytes=scratch,.data_byte_capacity=sizeof scratch};
    struct native_tree_context tree={.parser=&parser,.reader=&reader,.limit=32};
    uintptr_t definition_handle=macro_test_open_definition_handle(1);
    struct native_macro_registry registry={.parser=&parser,.source=(const uint8_t *)source,.tree=&tree,
        .definition_handle=definition_handle,.capacity=1};
    assert(native_macro_register(&registry,next_form(&parser,&compiler,&reader))==1);
    uintptr_t invocation=next_form(&parser,&compiler,&reader),count=parser.count;
    uintptr_t binding_handle=psl_rt_value_handle_open();
    struct native_macro_call call={.registry=&registry,.binding_handle=binding_handle,.capacity=2,.step_limit=32};
    struct native_macro_expansion result={0};
    parser.environment=NULL;
    assert(!native_macroexpand_1(&call,invocation,&result));
    assert(call.error && !call.count && !tree.depth);
    assert(parser.count==count && reader.count==count && result.form==invocation && !result.expanded);
    assert(psl_rt_value_handle_get(binding_handle)==PSL_NIL);
    psl_rt_value_handle_close(binding_handle);
    macro_test_close_definition_handle(definition_handle);
    assert(psl_rt_live_value_handles()==0);
}
int main(void) {
    null_reader_nil_key_rejects_safely();
    explicit_nil_default_identity();
    memset(names,0,sizeof names); memset(packages,0,sizeof packages); memset(symbols,0,sizeof symbols);
    memset(present,0,sizeof present); memset(uses,0,sizeof uses); memset(aliases,0,sizeof aliases);
    memset(identities,0,sizeof identities); memset(nodes,0,sizeof nodes); memset(scratch,0,sizeof scratch);
    const char *text="(defmacro choose (x &rest tail &key ((:actual y) 3 supplied) (z y) &aux (w z)) (declare (ignore tail supplied)) (list 'wrap+ x w)) (choose number) (choose number :actual 7 :actual 9) (choose number :unknown 7) (choose number :actual) (choose number :unknown 7 :allow-other-keys nil :allow-other-keys t) (choose number :unknown 7 :allow-other-keys 0) (defmacro fail (&key (y (list unknown_key_element))) y) (fail) (fail :y number) (defmacro choose (&key ((:actual y extra) 3)) y)";
    struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,
        .symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,.aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner={(const uint8_t *)text,strlen(text),0,0};
    struct psl_token token={0};
    struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=24000};
    struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=24000,.environment=&reader};
    struct psl_parsed_integer integer={0};
    struct native_compile_context compiler={.parser=&parser,.source=(const uint8_t *)text,.integer=&integer,.data_bytes=scratch,.data_byte_capacity=sizeof scratch};
    struct native_tree_context tree={.parser=&parser,.reader=&reader,.limit=32};
    uintptr_t definition_handle=macro_test_open_definition_handle(2);
    struct native_macro_registry registry={.parser=&parser,.source=(const uint8_t *)text,.tree=&tree,.definition_handle=definition_handle,.capacity=2};
    assert(native_macro_register(&registry,next_form(&parser,&compiler,&reader))==1);
    struct native_macro_call call={.registry=&registry,.binding_handle=psl_rt_value_handle_open(),.capacity=6,.step_limit=32};
    struct native_macro_expansion result={0};
    uintptr_t form=0;
    for(unsigned supplied=0;supplied<2;++supplied) {
        form=next_form(&parser,&compiler,&reader);
        uintptr_t count=parser.count,symbol_count=env.symbol_count,name_count=env.name_count;
        struct psl_ast_node before[512]; assert(count<=512); memcpy(before,nodes,count*sizeof *nodes);
        assert(native_macroexpand_1(&call,form,&result) && result.expanded);
        assert(!memcmp(before,nodes,count*sizeof *nodes));
        assert(env.symbol_count==symbol_count && env.name_count==name_count);
        uintptr_t x=nodes[nodes[form-1].first-1].next;
        uintptr_t out_x=nodes[nodes[result.form-1].first-1].next;
        assert(identities[out_x-1].symbol==identities[x-1].symbol && identities[out_x-1].origin==x);
        uintptr_t out_y=nodes[out_x-1].next;
        if(supplied) {
            uintptr_t argument=nodes[nodes[x-1].next-1].next;
            assert(nodes[out_y-1].start==nodes[argument-1].start);
            assert(nodes[out_y-1].length==nodes[argument-1].length);
            assert(identities[out_y-1].origin==argument);
            /* The rest binding keeps the complete original keyword argument list. */
            uintptr_t rest=nodes[native_macro_binding_form_at(&call,2)-1].first;
            assert(identities[rest-1].symbol==identities[nodes[x-1].next-1].symbol);
            assert(identities[rest-1].origin==nodes[x-1].next);
        } else assert(identities[out_y-1].origin==form);
        assert(native_tree_verify(&tree,result.form));
    }
    call.capacity=5;
    rejected(&call,form,&result,NATIVE_MACRO_CAPACITY);
    call.capacity=6;
    uintptr_t capacity=parser.capacity;
    parser.capacity=parser.count+3;
    rejected(&call,form,&result,NATIVE_MACRO_SYNTAX_CAPACITY);
    parser.capacity=capacity;
    for(unsigned invalid=0;invalid<3;++invalid)
        rejected(&call,next_form(&parser,&compiler,&reader),&result,NATIVE_MACRO_ARITY);
    form=next_form(&parser,&compiler,&reader);
    assert(native_macroexpand_1(&call,form,&result) && result.expanded);
    assert(native_tree_verify(&tree,result.form));
    assert(native_macro_register(&registry,next_form(&parser,&compiler,&reader))==2);
    rejected(&call,next_form(&parser,&compiler,&reader),&result,NATIVE_MACRO_REFERENCE);
    form=next_form(&parser,&compiler,&reader);
    assert(native_macroexpand_1(&call,form,&result) && result.expanded);
    uintptr_t argument=nodes[nodes[nodes[form-1].first-1].next-1].next;
    assert(identities[result.form-1].symbol==identities[argument-1].symbol);
    assert(identities[result.form-1].origin==argument);
    uintptr_t before_definitions[2][3];
    for(unsigned i=1;i<=registry.count;++i) {
        before_definitions[i-1][0]=native_macro_definition_symbol_at(&registry,i);
        before_definitions[i-1][1]=native_macro_definition_parameters_at(&registry,i);
        before_definitions[i-1][2]=native_macro_definition_body_at(&registry,i);
    }
    uintptr_t bad=next_form(&parser,&compiler,&reader),count=parser.count;
    assert(!native_macro_register(&registry,bad) && registry.error==NATIVE_MACRO_UNSUPPORTED);
    for(unsigned i=1;i<=registry.count;++i) {
        assert(before_definitions[i-1][0]==native_macro_definition_symbol_at(&registry,i));
        assert(before_definitions[i-1][1]==native_macro_definition_parameters_at(&registry,i));
        assert(before_definitions[i-1][2]==native_macro_definition_body_at(&registry,i));
    }
    assert(parser.count==count && reader.count==count);
    /* Large flat invocation lists must not require proportional C stack. */
    char *wide=malloc(120000);
    assert(wide);
    const char *prefix="(defmacro wide (&key value) value) (wide :value 42 ";
    size_t length=strlen(prefix); memcpy(wide,prefix,length);
    for(unsigned i=0;i<9999;++i) {
        const char *pair=":value 99 "; size_t size=strlen(pair);
        memcpy(wide+length,pair,size); length+=size;
    }
    wide[length++]=')'; wide[length]=0;
    scanner=(struct psl_scanner){(const uint8_t *)wide,length,0,0};
    memset(&token,0,sizeof token);
    parser.count=0; parser.error=0; reader.count=0; reader.error=0;
    compiler.source=(const uint8_t *)wide;
    registry.source=(const uint8_t *)wide; registry.count=0; registry.error=0;
    tree.error=0; call.error=0;
    assert(native_macro_register(&registry,next_form(&parser,&compiler,&reader))==1);
    form=next_form(&parser,&compiler,&reader);
    assert(native_macroexpand_1(&call,form,&result) && result.expanded);
    argument=nodes[nodes[nodes[form-1].first-1].next-1].next;
    assert(identities[result.form-1].origin==argument);
    assert(nodes[result.form-1].length==2);
    assert(!memcmp(wide+nodes[result.form-1].start,"42",2));
    assert(native_tree_verify(&tree,result.form));
    free(wide);
    psl_rt_value_handle_close(call.binding_handle);
    macro_test_close_definition_handle(definition_handle);
    puts("macro keyword API preserves caller/rest syntax and explicit NIL defaults, rejects a missing reader, chooses first duplicates and rolls back arity, capacity, defaults, invalid redefinition and 10,000-pair invocation lists");
}
