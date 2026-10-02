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
static struct native_source_identity identities[128];
static struct psl_ast_node nodes[128];
static uintptr_t sid(struct native_reader_environment *r,uintptr_t ref){assert(ref);return r->identities[ref-1].symbol;}
int main(void){
 const char *text="(car CAR cl:car psl::car |car| :hello ::hello #:x #:x 0 -0 #xFF 1.25f0 2d0 \"text\" 'wrap+)";
 struct native_ct_environment env={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=16,.symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=32,.aliases=aliases,.alias_capacity=8};
 assert(native_ct_seed_standard(&env));
 struct psl_scanner scanner={(const uint8_t *)text,strlen(text),0,0};
 struct psl_token token={0};
 struct psl_parser parser={.scanner=&scanner,.token=&token,.nodes=nodes,.capacity=128};
 struct psl_parsed_integer integer={0};
 struct native_compile_context context={.parser=&parser,.source=(const uint8_t *)text,.integer=&integer,.data_bytes=scratch,.data_byte_capacity=sizeof scratch};
 struct native_reader_environment reader={.environment=&env,.identities=identities,.capacity=128};
 uintptr_t root=parser_next(&parser);assert(root&&parser.error==0);
 assert(native_resolve_source_identities(&context,&reader)&&reader.count==parser.count);
 uintptr_t refs[32],count=0;
 for(uintptr_t ref=nodes[root-1].first;ref;ref=nodes[ref-1].next)refs[count++]=ref;
 assert(count==16);
 uintptr_t car=sid(&reader,refs[0]);assert(car);
 for(unsigned i=1;i<4;i++)assert(sid(&reader,refs[i])==car);
 assert(sid(&reader,refs[4])!=car&&sid(&reader,refs[4]));
 assert(sid(&reader,refs[5])==sid(&reader,refs[6])&&sid(&reader,refs[5]));
 uintptr_t fresh=sid(&reader,refs[7]);
 assert(fresh&&sid(&reader,refs[8])&&fresh!=sid(&reader,refs[8]));
 for(unsigned i=9;i<15;i++)assert(!sid(&reader,refs[i]));
 assert(nodes[refs[15]-1].kind==3&&!sid(&reader,refs[15]));
 assert(sid(&reader,nodes[refs[15]-1].first));
 for(uintptr_t ref=1;ref<=parser.count;ref++)assert(identities[ref-1].origin==ref);
 uintptr_t names_before=env.name_count,symbols_before=env.symbol_count;
 assert(native_resolve_source_identities(&context,&reader));
 assert(env.name_count==names_before&&env.symbol_count==symbols_before&&sid(&reader,refs[7])==fresh);
 /* Capacity failure has no partially interpreted symbols. */
 reader.count=0;reader.capacity=0;
 assert(!native_resolve_source_identities(&context,&reader)&&reader.failure==1&&reader.count==0);
 assert(env.name_count==names_before&&env.symbol_count==symbols_before);
 /* An unresolved external name reports its original AST node. Retry must
    retain the already-read uninterned symbol rather than creating another. */
 text="(#:prior unknown:foo)";
 scanner=(struct psl_scanner){(const uint8_t *)text,strlen(text),0,0};
 token=(struct psl_token){0};parser.count=0;parser.has_token=0;parser.error=0;
 context.source=(const uint8_t *)text;
 reader=(struct native_reader_environment){.environment=&env,.identities=identities,.capacity=128};
 root=parser_next(&parser);assert(root&&parser.count==3);
 assert(!native_resolve_source_identities(&context,&reader));
 assert(reader.failure==3&&reader.error==3&&reader.count==2&&env.error==6);
 uintptr_t prior=sid(&reader,2);assert(prior&&symbols[prior-1].package==0);
 env.error=0;
 uintptr_t unknown=native_ct_make_package(&env,(const uint8_t *)"UNKNOWN",7);
 uintptr_t foo=native_ct_intern(&env,unknown,(const uint8_t *)"FOO",3);
 assert(native_ct_bind_symbol(&env,unknown,foo,1)==foo);
 symbols_before=env.symbol_count;names_before=env.name_count;
 reader.failure=0;reader.error=0;
 assert(native_resolve_source_identities(&context,&reader)&&reader.count==3);
 assert(sid(&reader,2)==prior&&sid(&reader,3)==foo&&env.symbol_count==symbols_before&&env.name_count==names_before);
 struct psl_ast_node before[128];memcpy(before,nodes,sizeof before);
 assert(native_resolve_source_identities(&context,&reader));
 assert(!memcmp(before,nodes,sizeof before));
 puts("native AST side identities preserve source spans, numeric nodes and fresh reader identities");
}
