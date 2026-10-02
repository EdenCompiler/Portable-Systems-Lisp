#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../bootstrap/frontend/environment.h"
#include "bootstrap_environment_index.h"
static uint8_t names[65536+128];
static struct native_ct_package packages[16];
static struct native_ct_symbol symbols[1024];
static struct native_ct_presence present[2048];
static struct native_ct_use uses[32];
static struct native_ct_alias aliases[8];
static uintptr_t make(struct native_ct_environment *e,const char *s) {
    return native_ct_make_package(e,(const uint8_t *)s,strlen(s));
}
static uintptr_t intern(struct native_ct_environment *e,uintptr_t p,const char *s) {
    return native_ct_intern(e,p,(const uint8_t *)s,strlen(s));
}
static uintptr_t find(struct native_ct_environment *e,uintptr_t p,const char *s) {
    return native_ct_find_symbol(e,p,(const uint8_t *)s,strlen(s));
}
int main(void) {
    struct native_ct_environment e={.names=names,.name_capacity=sizeof names,
       .packages=packages,.package_capacity=16,.symbols=symbols,.symbol_capacity=1024,
       .present=present,.present_capacity=2048,.uses=uses,.use_capacity=32,.aliases=aliases,.alias_capacity=8, TEST_INDEX_FIELDS};
    uintptr_t cl=make(&e,"COMMON-LISP"),psl=make(&e,"PSL"),source=make(&e,"SOURCE");
    uintptr_t key=make(&e,"KEYWORD");e.keyword_package=key;
    assert(cl && psl && source && key && e.error==0);
    assert(native_ct_add_alias(&e,cl,(const uint8_t *)"CL",2)==cl);
    assert(native_ct_find_package(&e,(const uint8_t *)"CL",2)==cl);
    assert(make(&e,"CL")==0 && e.error==2);e.error=0;
    uintptr_t load=intern(&e,cl,"LOAD"),psl_load=intern(&e,psl,"LOAD");
    assert(load && psl_load && load!=psl_load);
    assert(native_ct_bind_symbol(&e,cl,load,1)==load);
    assert(native_ct_link_use(&e,source,cl));
    assert(find(&e,source,"LOAD")==load && intern(&e,source,"LOAD")==load);
    uintptr_t wrap=intern(&e,psl,"WRAP+");
    assert(native_ct_bind_symbol(&e,source,wrap,0)==wrap);
    assert(find(&e,source,"WRAP+")==wrap);
    /* Interleaving package additions must not corrupt local presence chains. */
    uintptr_t x=intern(&e,cl,"X"),y=intern(&e,psl,"Y"),z=intern(&e,cl,"Z");
    assert(find(&e,cl,"X")==x && find(&e,cl,"Z")==z && find(&e,psl,"Y")==y);
    assert(find(&e,source,"X")==0); /* Internal names are not inherited. */
    assert(native_ct_bind_symbol(&e,cl,x,1)==x && find(&e,source,"X")==x);
    assert(native_ct_bind_symbol(&e,psl,psl_load,1)==psl_load);
    assert(native_ct_link_use(&e,source,psl));
    assert(find(&e,source,"LOAD")==0 && e.error==3);e.error=0;
    assert(native_ct_bind_symbol(&e,source,load,2)==load && find(&e,source,"LOAD")==load);
    assert(intern(&e,key,"K")==intern(&e,key,"K"));
    assert(intern(&e,source,"lower")!=intern(&e,source,"LOWER"));
    uint8_t long_name[65536];memset(long_name,'A',sizeof long_name);
    uintptr_t long_id=native_ct_intern(&e,source,long_name,sizeof long_name);
    assert(long_id && native_ct_find_symbol(&e,source,long_name,sizeof long_name)==long_id);
    uintptr_t old_names=e.name_count,old_symbols=e.symbol_count,old_present=e.present_count;
    e.symbol_capacity=e.symbol_count;
    assert(intern(&e,source,"FULL")==0 && e.error==1);
    assert(e.name_count==old_names && e.symbol_count==old_symbols && e.present_count==old_present);
    /* A latched failure must prevent subsequent successful-looking writes. */
    e.symbol_capacity=1024;
    assert(intern(&e,source,"BLOCKED")==0 && e.error==1);
    assert(make(&e,"BLOCKED-PACKAGE")==0 && e.error==1);
    assert(native_ct_add_alias(&e,cl,(const uint8_t *)"BLOCKED-ALIAS",13)==0);
    assert(e.name_count==old_names && e.symbol_count==old_symbols && e.present_count==old_present);
    e.error=0;
    assert(intern(&e,source,"RESUMED"));
    /* Invalid index configurations must fail before publishing a package. */
    const uintptr_t bad_counts[] = {3, 2048, UINTPTR_MAX};
    for (unsigned i=0; i<sizeof bad_counts/sizeof *bad_counts; ++i) {
        struct native_ct_environment bad={.names=names,.name_capacity=sizeof names,
            .packages=packages,.package_capacity=16,.buckets=test_buckets,
            .bucket_count=bad_counts[i],.bucket_capacity=sizeof test_buckets/sizeof *test_buckets};
        assert(!make(&bad,"BAD") && bad.error==1);
        assert(!bad.package_count && !bad.name_count);
    }
    struct native_ct_environment bad={.names=names,.name_capacity=sizeof names,
        .packages=packages,.package_capacity=16,.bucket_count=1024,.bucket_capacity=1024};
    assert(!make(&bad,"BAD") && bad.error==1 && !bad.package_count && !bad.name_count);
    bad.error=0;bad.buckets=test_buckets;bad.bucket_capacity=1023;
    assert(!make(&bad,"BAD") && bad.error==1 && !bad.package_count && !bad.name_count);
    puts("native build-host package identities, imports, visibility and bounds passed");
}
