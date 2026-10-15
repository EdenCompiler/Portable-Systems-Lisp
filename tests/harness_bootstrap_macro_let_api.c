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
static int rejects_constant_name(const char *name) {
    static char source[512];
    memset(names,0,sizeof names); memset(packages,0,sizeof packages); memset(symbols,0,sizeof symbols);
    memset(present,0,sizeof present); memset(uses,0,sizeof uses); memset(aliases,0,sizeof aliases);
    memset(identities,0,sizeof identities); memset(nodes,0,sizeof nodes); memset(scratch,0,sizeof scratch);
    int used=snprintf(source,sizeof source,"(defmacro bad_constant () (let ((%s '1)) 1)) (bad_constant)",name);
    assert(used>0 && (size_t)used<sizeof source);
    struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,
        .symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,
        .aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner={(const uint8_t *)source,strlen(source),0,0};
    struct psl_token token={0};
    struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=256};
    struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=256,.environment=&reader};
    struct psl_parsed_integer integer={0};
    struct native_compile_context compiler={.parser=&parser,.source=(const uint8_t *)source,.integer=&integer,
        .data_bytes=scratch,.data_byte_capacity=sizeof scratch};
    struct native_tree_context tree={.parser=&parser,.reader=&reader,.limit=32};
    struct native_macro_definition definitions[1]={{0}};
    struct native_macro_registry registry={.parser=&parser,.source=(const uint8_t *)source,.tree=&tree,.definitions=definitions,.capacity=1};
    uintptr_t definition=parser_next(&parser);
    assert(definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,definition)==1);
    uintptr_t form=parser_next(&parser);
    assert(form && native_resolve_source_identities(&compiler,&reader));
    env.name_capacity=env.name_count;
    uintptr_t saved_name_count=env.name_count, saved_cursor=env.read_cursor;
    uintptr_t count=parser.count;
    struct psl_ast_node before[256]; memcpy(before,nodes,count*sizeof *nodes);
    struct native_macro_binding bindings[2]={{0}};
    struct native_macro_call call={.registry=&registry,.bindings=bindings,.capacity=2,.step_limit=32};
    struct native_macro_expansion result={0};
    assert(!native_macroexpand_1(&call,form,&result));
    assert(call.error==NATIVE_MACRO_UNSUPPORTED && !call.count && !tree.depth);
    assert(env.name_count==saved_name_count && env.read_cursor==saved_cursor);
    assert(parser.count==count && reader.count==count && !memcmp(before,nodes,count*sizeof *nodes));
    return 1;
}
static const char *const cl_constant_names[]={
    "PI",
    "SHORT-FLOAT-NEGATIVE-EPSILON",
    "MOST-NEGATIVE-SINGLE-FLOAT",
    "INTERNAL-TIME-UNITS-PER-SECOND",
    "BOOLE-XOR",
    "LEAST-POSITIVE-DOUBLE-FLOAT",
    "MOST-POSITIVE-SHORT-FLOAT",
    "BOOLE-CLR",
    "BOOLE-C2",
    "BOOLE-NOR",
    "LEAST-NEGATIVE-SHORT-FLOAT",
    "LEAST-NEGATIVE-DOUBLE-FLOAT",
    "MOST-NEGATIVE-FIXNUM",
    "T",
    "BOOLE-ANDC2",
    "DOUBLE-FLOAT-NEGATIVE-EPSILON",
    "LEAST-POSITIVE-NORMALIZED-LONG-FLOAT",
    "LEAST-NEGATIVE-SINGLE-FLOAT",
    "NIL",
    "LEAST-POSITIVE-NORMALIZED-SINGLE-FLOAT",
    "BOOLE-IOR",
    "BOOLE-SET",
    "LONG-FLOAT-EPSILON",
    "LEAST-POSITIVE-SINGLE-FLOAT",
    "ARRAY-TOTAL-SIZE-LIMIT",
    "BOOLE-ORC1",
    "MULTIPLE-VALUES-LIMIT",
    "ARRAY-RANK-LIMIT",
    "ARRAY-DIMENSION-LIMIT",
    "LEAST-NEGATIVE-NORMALIZED-SHORT-FLOAT",
    "LAMBDA-PARAMETERS-LIMIT",
    "LEAST-NEGATIVE-NORMALIZED-SINGLE-FLOAT",
    "MOST-POSITIVE-DOUBLE-FLOAT",
    "LEAST-NEGATIVE-NORMALIZED-LONG-FLOAT",
    "CHAR-CODE-LIMIT",
    "LEAST-NEGATIVE-NORMALIZED-DOUBLE-FLOAT",
    "SHORT-FLOAT-EPSILON",
    "BOOLE-1",
    "LONG-FLOAT-NEGATIVE-EPSILON",
    "MOST-NEGATIVE-LONG-FLOAT",
    "LEAST-POSITIVE-NORMALIZED-SHORT-FLOAT",
    "LEAST-POSITIVE-LONG-FLOAT",
    "LAMBDA-LIST-KEYWORDS",
    "BOOLE-C1",
    "SINGLE-FLOAT-EPSILON",
    "BOOLE-2",
    "MOST-POSITIVE-LONG-FLOAT",
    "BOOLE-ANDC1",
    "DOUBLE-FLOAT-EPSILON",
    "BOOLE-ORC2",
    "CALL-ARGUMENTS-LIMIT",
    "BOOLE-AND",
    "LEAST-POSITIVE-SHORT-FLOAT",
    "BOOLE-EQV",
    "SINGLE-FLOAT-NEGATIVE-EPSILON",
    "MOST-POSITIVE-FIXNUM",
    "LEAST-POSITIVE-NORMALIZED-DOUBLE-FLOAT",
    "MOST-NEGATIVE-SHORT-FLOAT",
    "LEAST-NEGATIVE-LONG-FLOAT",
    "MOST-POSITIVE-SINGLE-FLOAT",
    "BOOLE-NAND",
    "MOST-NEGATIVE-DOUBLE-FLOAT",
};
static int rejects_constant_parameter(const char *name, const char *marker) {
    static char source[512];
    memset(names,0,sizeof names); memset(packages,0,sizeof packages); memset(symbols,0,sizeof symbols);
    memset(present,0,sizeof present); memset(uses,0,sizeof uses); memset(aliases,0,sizeof aliases);
    memset(identities,0,sizeof identities); memset(nodes,0,sizeof nodes); memset(scratch,0,sizeof scratch);
    int used=snprintf(source,sizeof source,"(defmacro bad (%s%s) '1)",marker,name);
    assert(used>0 && (size_t)used<sizeof source);
    struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,
        .symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,
        .aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    struct psl_scanner scanner={(const uint8_t *)source,strlen(source),0,0};
    struct psl_token token={0};
    struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=256};
    struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=256,.environment=&reader};
    struct psl_parsed_integer integer={0};
    struct native_compile_context compiler={.parser=&parser,.source=(const uint8_t *)source,.integer=&integer};
    struct native_tree_context tree={.parser=&parser,.reader=&reader,.limit=32};
    struct native_macro_definition definitions[1]={{0}};
    struct native_macro_registry registry={.parser=&parser,.source=(const uint8_t *)source,.tree=&tree,.definitions=definitions,.capacity=1};
    uintptr_t definition=parser_next(&parser);
    assert(definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,definition)==0);
    assert(registry.error==10 && registry.count==0);
    return 1;
}
int main(void) {
    for (size_t i=0;i<sizeof cl_constant_names/sizeof cl_constant_names[0];++i)
        assert(rejects_constant_name(cl_constant_names[i]));
    static const char *const parameter_markers[]={"","&optional ","&key ","&aux ","&rest ","&whole "};
    for (size_t i=0;i<sizeof cl_constant_names/sizeof cl_constant_names[0];++i)
        for (size_t j=0;j<sizeof parameter_markers/sizeof parameter_markers[0];++j)
            assert(rejects_constant_parameter(cl_constant_names[i],parameter_markers[j]));
    const char *text="(defmacro letter (x) (let ((saved x) (x '3)) `(wrap+ ,saved ,x))) (letter number) (defmacro fail_letter (x) (let ((saved x) (bad missing_let_binding)) `(wrap+ ,saved ,bad))) (fail_letter number) (defmacro other_constant () (let ((other::most-positive-fixnum '1)) '7)) (other_constant) (defmacro other_parameter (other::pi) '9) (other_parameter 7)";
    struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,
        .symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,
        .aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&env));
    const uint8_t other_name[]="OTHER";
    uintptr_t other_package=native_ct_make_package(&env,other_name,5);
    assert(other_package);
    struct psl_scanner scanner={(const uint8_t *)text,strlen(text),0,0};
    struct psl_token token={0};
    struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=256};
    struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=256,.environment=&reader};
    struct psl_parsed_integer integer={0};
    struct native_compile_context compiler={.parser=&parser,.source=(const uint8_t *)text,.integer=&integer,
        .data_bytes=scratch,.data_byte_capacity=sizeof scratch};
    struct native_tree_context tree={.parser=&parser,.reader=&reader,.limit=32};
    struct native_macro_definition definitions[4]={{0}};
    struct native_macro_registry registry={.parser=&parser,.source=(const uint8_t *)text,.tree=&tree,.definitions=definitions,.capacity=4};
    uintptr_t definition=parser_next(&parser);
    assert(definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,definition)==1);
    uintptr_t form=parser_next(&parser);
    assert(form && native_resolve_source_identities(&compiler,&reader));
    uintptr_t count=parser.count;
    struct psl_ast_node before[256]; memcpy(before,nodes,count*sizeof *nodes);
    struct native_macro_binding bindings[3]={{0}};
    struct native_macro_call call={.registry=&registry,.bindings=bindings,.capacity=2,.step_limit=32};
    struct native_macro_expansion result={0};
    assert(!native_macroexpand_1(&call,form,&result));
    assert(call.error==NATIVE_MACRO_CAPACITY && !call.count && !tree.depth);
    assert(parser.count==count && reader.count==count && !memcmp(before,nodes,count*sizeof *nodes));
    call.capacity=3; call.error=0; tree.error=0;
    assert(native_macroexpand_1(&call,form,&result) && result.expanded);
    assert(parser.count>count && reader.count==parser.count && !memcmp(before,nodes,count*sizeof *nodes));
    assert(native_tree_verify(&tree,result.form));
    uintptr_t package=native_ct_find_package(&env,(const uint8_t *)"PSL",3);
    uintptr_t wrapper=native_ct_find_symbol(&env,package,(const uint8_t *)"WRAP+",5);
    uintptr_t head=nodes[result.form-1].first;
    uintptr_t first=nodes[head-1].next;
    uintptr_t second=nodes[first-1].next;
    uintptr_t argument=nodes[nodes[form-1].first-1].next;
    assert(wrapper && identities[head-1].symbol==wrapper);
    assert(identities[first-1].symbol==identities[argument-1].symbol && identities[first-1].origin==argument);
    assert(text[nodes[second-1].start]=='3' && !nodes[second-1].next);
    uintptr_t failed_definition=parser_next(&parser);
    assert(failed_definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,failed_definition)==2);
    uintptr_t failed_form=parser_next(&parser);
    assert(failed_form && native_resolve_source_identities(&compiler,&reader));
    count=parser.count; memcpy(before,nodes,count*sizeof *nodes);
    call.error=0; tree.error=0; call.capacity=3;
    assert(!native_macroexpand_1(&call,failed_form,&result));
    assert(call.error==NATIVE_MACRO_REFERENCE && !call.count && !tree.depth);
    assert(parser.count==count && reader.count==count && !memcmp(before,nodes,count*sizeof *nodes));
    uintptr_t other_definition=parser_next(&parser);
    assert(other_definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,other_definition)==3);
    uintptr_t other_form=parser_next(&parser);
    assert(other_form && native_resolve_source_identities(&compiler,&reader));
    call.error=0; tree.error=0;
    assert(native_macroexpand_1(&call,other_form,&result) && result.expanded);
    uintptr_t other_symbol=native_ct_find_symbol(&env,other_package,
        (const uint8_t *)"MOST-POSITIVE-FIXNUM",20);
    assert(other_symbol && symbols[other_symbol-1].package==other_package);
    assert(native_tree_verify(&tree,result.form));
    uintptr_t parameter_definition=parser_next(&parser);
    assert(parameter_definition && native_resolve_source_identities(&compiler,&reader));
    assert(native_macro_register(&registry,parameter_definition)==4);
    uintptr_t parameter_form=parser_next(&parser);
    assert(parameter_form && native_resolve_source_identities(&compiler,&reader));
    call.error=0; tree.error=0;
    assert(native_macroexpand_1(&call,parameter_form,&result) && result.expanded);
    uintptr_t other_pi=native_ct_find_symbol(&env,other_package,(const uint8_t *)"PI",2);
    uintptr_t definition_head=nodes[parameter_definition-1].first;
    uintptr_t macro_name=nodes[definition_head-1].next;
    uintptr_t lambda_list=nodes[macro_name-1].next;
    uintptr_t parameter=nodes[lambda_list-1].first;
    assert(other_pi && identities[parameter-1].symbol==other_pi && symbols[other_pi-1].package==other_package);
    assert(native_tree_verify(&tree,result.form));
    puts("macro LET API preserves lexical origins, rejects the CL constant catalogue, accepts same-spelling package symbols and rolls back capacity/evaluation errors");
    return 0;
}
