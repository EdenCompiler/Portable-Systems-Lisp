#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../bootstrap/frontend/environment.h"
static uint8_t names[200000];
static struct native_ct_package packages[16];
static struct native_ct_symbol symbols[1400];
static struct native_ct_presence present[2048];
static struct native_ct_use uses[32];
static struct native_ct_alias aliases[8];
static uintptr_t read_symbol(struct native_ct_environment *e,const char *text) {
    return native_ct_read_symbol(e,(const uint8_t *)text,strlen(text));
}
static void spelling(struct native_ct_environment *e,uintptr_t id,const char *name,uintptr_t package) {
    assert(id && symbols[id-1].package==package && symbols[id-1].length==strlen(name));
    assert(memcmp(names+symbols[id-1].name,name,strlen(name))==0);assert(e->error==0);
}
int main(void) {
    struct native_ct_environment e={.names=names,.name_capacity=sizeof names,
       .packages=packages,.package_capacity=16,.symbols=symbols,.symbol_capacity=1400,
       .present=present,.present_capacity=2048,.uses=uses,.use_capacity=32,
       .aliases=aliases,.alias_capacity=8};
    assert(native_ct_seed_standard(&e)==1);
    const char *cars[]={"car","CAR","cl:car","COMMON-LISP:CAR","cl::car","cl:|CAR|", "psl::car"};
    uintptr_t car=read_symbol(&e,cars[0]);spelling(&e,car,"CAR",1);
    for(unsigned i=1;i<sizeof cars/sizeof cars[0];i++) assert(read_symbol(&e,cars[i])==car);
    uintptr_t lower=read_symbol(&e,"|car|");spelling(&e,lower,"car",5);assert(lower!=car);
    assert(read_symbol(&e,"\\c\\a\\r")==lower);
    uintptr_t mix=read_symbol(&e,"a|Bc|d");spelling(&e,mix,"ABcD",5);
    spelling(&e,read_symbol(&e,"|name with spaces:colon|"),"name with spaces:colon",5);
    spelling(&e,read_symbol(&e,"name\\:colon"),"NAME:COLON",5);
    uintptr_t empty=read_symbol(&e,"||");spelling(&e,empty,"",5);
    uintptr_t keyword=read_symbol(&e,":hello");spelling(&e,keyword,"HELLO",4);
    assert(read_symbol(&e,":HELLO")==keyword);
    assert(read_symbol(&e,"::hello")==keyword);
    spelling(&e,read_symbol(&e,":||"),"",4);
    uintptr_t fresh=read_symbol(&e,"#:car");spelling(&e,fresh,"CAR",0);
    assert(read_symbol(&e,"#:car")!=fresh);
    spelling(&e,read_symbol(&e,"#:"),"",0);
    spelling(&e,read_symbol(&e,"cl::new-internal"),"NEW-INTERNAL",1);
    uintptr_t ordinary=read_symbol(&e,"new-internal");spelling(&e,ordinary,"NEW-INTERNAL",5);
    spelling(&e,read_symbol(&e,"psl:wrap+"),"WRAP+",2);
    assert(read_symbol(&e,"wrap+")==read_symbol(&e,"psl:wrap+"));
    assert(read_symbol(&e,"load")==read_symbol(&e,"cl:load"));
    assert(read_symbol(&e,"load")!=read_symbol(&e,"psl:load"));
    assert(read_symbol(&e,"ffi:call")==read_symbol(&e,"psl.ffi:call"));
    const char *invalid[]={"cl:new-internal","missing:foo","|cl|:car","cl:","cl::",":", "cl:::car", "a:b:c", "|bad", "bad\\", "#::car", "a(b)", "a;bad", "a\"bad", "a b"};
    for(unsigned i=0;i<sizeof invalid/sizeof invalid[0];i++) {
        uintptr_t saved_names=e.name_count,saved_symbols=e.symbol_count;
        assert(read_symbol(&e,invalid[i])==0 && e.error);
        assert(e.name_count==saved_names && e.symbol_count==saved_symbols);e.error=0;
    }
    char long_name[65539];memset(long_name,'a',sizeof long_name-1);long_name[sizeof long_name-1]=0;
    uintptr_t long_id=read_symbol(&e,long_name);
    assert(long_id && symbols[long_id-1].length==sizeof long_name-1);
    assert(read_symbol(&e,long_name)==long_id);
    puts("native reader package qualification, case, escapes and fresh identities passed");
}
