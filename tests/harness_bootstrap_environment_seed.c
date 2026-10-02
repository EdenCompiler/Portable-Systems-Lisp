#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../bootstrap/frontend/environment.h"
#include "bootstrap_environment_index.h"
static uint8_t names[32768];
static struct native_ct_package packages[16];
static struct native_ct_symbol symbols[1200];
static struct native_ct_presence present[2048];
static struct native_ct_use uses[32];
static struct native_ct_alias aliases[8];
static struct native_ct_environment create(void) {
    struct native_ct_environment e={.names=names,.name_capacity=sizeof names,
       .packages=packages,.package_capacity=16,.symbols=symbols,.symbol_capacity=1200,
       .present=present,.present_capacity=2048,.uses=uses,.use_capacity=32,
       .aliases=aliases,.alias_capacity=8, TEST_INDEX_FIELDS};return e;
}
static uintptr_t find(struct native_ct_environment *e,uintptr_t p,const char *s) {
    return native_ct_find_symbol(e,p,(const uint8_t *)s,strlen(s));
}
int main(int argc,char **argv) {
    assert(argc==2);
    struct native_ct_environment e=create();
    assert(native_ct_seed_standard(&e)==1 && e.error==0);
    assert(e.package_count==5 && e.symbol_count==1049);
    assert(native_ct_find_package(&e,(const uint8_t *)"CL",2)==1);
    assert(native_ct_find_package(&e,(const uint8_t *)"FFI",3)==3);
    assert(find(&e,5,"LOAD")==find(&e,1,"LOAD"));
    assert(find(&e,5,"LOAD")!=find(&e,2,"LOAD"));
    assert(find(&e,5,"EXPORT")==find(&e,1,"EXPORT"));
    assert(find(&e,5,"WRAP+")==find(&e,2,"WRAP+"));
    assert(e.nil_symbol==find(&e,1,"NIL") && e.true_symbol==find(&e,1,"T"));
    FILE *catalogue=fopen(argv[1],"r");assert(catalogue);
    char package[128],name[128];unsigned count=0;
    while(fscanf(catalogue,"%127s\t%127s",package,name)==2) {
        uintptr_t owner=native_ct_find_package(&e,(const uint8_t *)package,strlen(package));
        uintptr_t symbol=find(&e,owner,name);assert(symbol && e.error==0);
        assert(symbols[symbol-1].package==owner);
        char qualified[256];
        int length=snprintf(qualified,sizeof qualified,"%s:%s",package,name);
        assert(length>0 && (size_t)length<sizeof qualified);
        assert(native_ct_read_symbol(&e,(const uint8_t *)qualified,(uintptr_t)length)==symbol);
        uintptr_t source=find(&e,5,name);
        if(owner==1) assert(source==symbol);
        if(owner==2 && !find(&e,1,name)) assert(source==symbol);
        ++count;
    }
    assert(count==1049 && fclose(catalogue)==0);
    uintptr_t saved_names=e.name_count;
    assert(find(&e,5,"WRAP+") && e.name_count==saved_names);
    assert(native_ct_seed_standard(&e)==0 && e.error==2);
    for(unsigned capacity=0;capacity<=5;capacity++) {
        e=create();e.package_capacity=capacity;
        if(capacity<5) assert(native_ct_seed_standard(&e)==0 && e.error==1);
        else assert(native_ct_seed_standard(&e)==1 && e.error==0);
    }
    e=create();e.symbol_capacity=8;
    assert(native_ct_seed_standard(&e)==0 && e.error==1 && e.symbol_count==8);
    uintptr_t partial_names=e.name_count, partial_symbols=e.symbol_count;
    assert(native_ct_intern(&e,5,(const uint8_t *)"BLOCKED",7)==0 && e.error==1);
    assert(e.name_count==partial_names && e.symbol_count==partial_symbols);
    e=create();e.name_count=1;
    assert(native_ct_seed_standard(&e)==0 && e.error==2 && e.package_count==0);
    puts("native build-host catalogue matches every Stage 0 package export");
}
