#include "../bootstrap/frontend/environment.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#ifndef TEST_BUCKET_COUNT
#define TEST_BUCKET_COUNT 1024
#endif
static uintptr_t buckets[32*1024];
static uint8_t names[200000];
static struct native_ct_package packages[32];
static struct native_ct_symbol symbols[2400];
static struct native_ct_presence present[3000];
static struct native_ct_use uses[128];
static struct native_ct_alias aliases[8];
static uintptr_t intern(struct native_ct_environment *e,uintptr_t p,const char *n){return native_ct_intern(e,p,(const uint8_t *)n,strlen(n));}
static uintptr_t find(struct native_ct_environment *e,uintptr_t p,const char *n){return native_ct_find_symbol(e,p,(const uint8_t *)n,strlen(n));}
static uintptr_t package(struct native_ct_environment *e,const char *n){return native_ct_make_package(e,(const uint8_t *)n,strlen(n));}
int main(void){
 struct native_ct_environment e={.names=names,.name_capacity=sizeof names,.packages=packages,.package_capacity=32,.symbols=symbols,.symbol_capacity=2400,.present=present,.present_capacity=3000,.uses=uses,.use_capacity=128,.aliases=aliases,.alias_capacity=8,.buckets=buckets,.bucket_count=TEST_BUCKET_COUNT,.bucket_capacity=32*1024};
 assert(native_ct_seed_standard(&e));
 uintptr_t a=package(&e,"A"),b=package(&e,"B"),c=package(&e,"C"),d=package(&e,"D");
 uintptr_t ax=intern(&e,a,"X"), bx=intern(&e,b,"X");
 assert(native_ct_export_symbol(&e,a,ax)==ax);
 assert(native_ct_export_symbol(&e,b,bx)==bx);
 assert(native_ct_use_package(&e,c,a));
 uintptr_t use_count=e.use_count, c_uses=packages[c-1].uses;
 assert(!native_ct_use_package(&e,c,b)&&e.error==3);
 assert(e.use_count==use_count&&packages[c-1].uses==c_uses&&find(&e,c,"X")==ax);e.error=0;
 /* Import conflicts cannot create a local binding. */
 uintptr_t presence_count=e.present_count;
 assert(!native_ct_import_symbol(&e,c,bx)&&e.error==3&&e.present_count==presence_count);e.error=0;
 assert(native_ct_import_symbol(&e,d,ax)==ax&&symbols[ax-1].package==a);
 assert(native_ct_export_symbol(&e,d,ax)==ax);
 assert(native_ct_use_package(&e,c,d)&&find(&e,c,"X")==ax);
 assert(native_ct_import_symbol(&e,c,ax)==ax);
 /* Export checks every package already using the exporter. */
 uintptr_t ay=intern(&e,a,"Y"),cy=intern(&e,c,"Y");
 presence_count=e.present_count;
 assert(!native_ct_export_symbol(&e,a,ay)&&e.error==3&&e.present_count==presence_count);e.error=0;
 assert(find(&e,c,"Y")==cy);
 assert(native_ct_bind_symbol(&e,c,cy,2)==cy);
 assert(native_ct_export_symbol(&e,a,ay)==ay&&find(&e,c,"Y")==cy);
 assert(native_ct_use_package(&e,b,d)==0&&e.error==3);e.error=0;
 uintptr_t internal=intern(&e,b,"INTERNAL");
 assert(native_ct_use_package(&e,c,b)==0&&e.error==3);e.error=0;
 assert(find(&e,c,"INTERNAL")==0&&internal);
 /* Exporting an inherited symbol preserves identity and makes it present. */
 uintptr_t q=package(&e,"Q");assert(native_ct_use_package(&e,q,a));
 assert(native_ct_export_symbol(&e,q,ax)==ax&&find(&e,q,"X")==ax&&symbols[ax-1].package==a);
 /* Shadowing resolves a use conflict without changing either home symbol. */
 uintptr_t shadow=native_ct_shadow_name(&e,c,(const uint8_t *)"X",1);
 assert(shadow==ax); /* Already imported; SHADOW retains that present identity. */
 assert(native_ct_use_package(&e,c,b)&&find(&e,c,"X")==ax);
 uintptr_t old_presence=packages[c-1].present;
 assert(!native_ct_unintern_symbol(&e,c,ax)&&e.error==3);
 assert(packages[c-1].present==old_presence&&find(&e,c,"X")==ax);e.error=0;
 /* Replacing a package's own symbol detaches only its home relationship. */
 uintptr_t own=intern(&e,d,"OWN"),foreign=intern(&e,a,"OWN");
 assert(native_ct_export_symbol(&e,d,own)==own);
 assert(native_ct_shadowing_import(&e,d,foreign)==foreign);
 assert(symbols[own-1].package==0&&symbols[foreign-1].package==a);
 assert(find(&e,d,"OWN")==foreign);
 assert(native_ct_unintern_symbol(&e,d,foreign)&&symbols[foreign-1].package==a);
 assert(!native_ct_unintern_symbol(&e,d,foreign)&&e.error==0);
 /* Shadow inherited symbols by creating a new present home identity. */
 uintptr_t qx=native_ct_shadow_name(&e,q,(const uint8_t *)"Y",1);
 assert(qx&&qx!=ay&&symbols[qx-1].package==q&&find(&e,q,"Y")==qx);
 assert(native_ct_unintern_symbol(&e,q,qx)&&symbols[qx-1].package==0&&find(&e,q,"Y")==ay);
 /* IMPORT adopts an uninterned home; SHADOWING-IMPORT preserves no home. */
 uintptr_t fresh=native_ct_read_symbol(&e,(const uint8_t *)"#:FRESH",7);
 assert(fresh && symbols[fresh-1].package==0);
 assert(native_ct_import_symbol(&e,d,fresh)==fresh && symbols[fresh-1].package==d);
 assert(native_ct_unintern_symbol(&e,d,fresh) && symbols[fresh-1].package==0);
 assert(native_ct_shadowing_import(&e,d,fresh)==fresh && symbols[fresh-1].package==0);
 assert(native_ct_import_symbol(&e,d,fresh)==fresh && symbols[fresh-1].package==d);
 assert(!native_ct_use_package(&e,e.keyword_package,a) && e.error==NATIVE_CT_OPERATION);e.error=0;
 assert(!native_ct_use_package(&e,e.keyword_package,e.keyword_package) && e.error==NATIVE_CT_OPERATION);e.error=0;
 uintptr_t fresh_keyword=native_ct_read_symbol(&e,(const uint8_t *)"#:FRESH-KEYWORD",15);
 assert(native_ct_import_symbol(&e,e.keyword_package,fresh_keyword)==fresh_keyword);
 assert(symbols[fresh_keyword-1].package==e.keyword_package);
 assert(native_ct_read_symbol(&e,(const uint8_t *)":FRESH-KEYWORD",14)==fresh_keyword);
 uintptr_t foreign_keyword=intern(&e,a,"FOREIGN-KEYWORD");
 assert(native_ct_import_symbol(&e,e.keyword_package,foreign_keyword)==foreign_keyword);
 assert(symbols[foreign_keyword-1].package==a);
 assert(native_ct_read_symbol(&e,(const uint8_t *)":FOREIGN-KEYWORD",16)==foreign_keyword);
 assert(native_ct_read_symbol(&e,(const uint8_t *)"keyword:FRESH-KEYWORD",21)==fresh_keyword);
 assert(native_ct_read_symbol(&e,(const uint8_t *)"keyword:FOREIGN-KEYWORD",23)==foreign_keyword);
 uintptr_t keyword_new=native_ct_read_symbol(&e,(const uint8_t *)"keyword:NEW-KEYWORD",19);
 assert(keyword_new && symbols[keyword_new-1].package==e.keyword_package);
 /* Removing head and interior collision entries must preserve other names. */
 uintptr_t chain1=intern(&e,d,"CHAIN1"),chain2=intern(&e,d,"CHAIN2"),chain3=intern(&e,d,"CHAIN3");
 assert(native_ct_unintern_symbol(&e,d,chain2) && !find(&e,d,"CHAIN2"));
 assert(find(&e,d,"CHAIN1")==chain1 && find(&e,d,"CHAIN3")==chain3);
 assert(native_ct_unintern_symbol(&e,d,chain3) && !find(&e,d,"CHAIN3"));
 assert(find(&e,d,"CHAIN1")==chain1);
 /* Visibility changes preserve identity, and repeated unuse is idempotent. */
 uintptr_t r=package(&e,"R"),sz=intern(&e,a,"SHARED-Z");
 assert(native_ct_export_symbol(&e,a,sz)==sz && native_ct_use_package(&e,r,a));
 assert(find(&e,r,"SHARED-Z")==sz);
 assert(native_ct_unexport_symbol(&e,r,sz)==sz && find(&e,r,"SHARED-Z")==sz);
 assert(native_ct_unexport_symbol(&e,a,sz)==sz && !find(&e,r,"SHARED-Z"));
 assert(native_ct_export_symbol(&e,a,sz)==sz && find(&e,r,"SHARED-Z")==sz);
 assert(native_ct_unuse_package(&e,r,a) && !find(&e,r,"SHARED-Z"));
 assert(native_ct_unuse_package(&e,r,a) && !find(&e,r,"SHARED-Z"));
 assert(native_ct_use_package(&e,r,a) && find(&e,r,"SHARED-Z")==sz);
 assert(native_ct_shadowing_import(&e,r,sz)==sz && native_ct_export_symbol(&e,r,sz)==sz);
 assert(native_ct_unexport_symbol(&e,r,sz)==sz && find(&e,r,"SHARED-Z")==sz);
 /* Out-of-room failures leave present and inherited bindings observable. */
 uintptr_t saved=e.present_count;e.present_capacity=saved;
 assert(!native_ct_import_symbol(&e,d,ay)&&e.error==1&&e.present_count==saved);e.error=0;
 assert(!find(&e,d,"Y"));
 uintptr_t full_symbol=native_ct_read_symbol(&e,(const uint8_t *)"#:FULL",6);
 assert(full_symbol && !symbols[full_symbol-1].package);
 assert(!native_ct_import_symbol(&e,d,full_symbol) && e.error==NATIVE_CT_CAPACITY);
 assert(!symbols[full_symbol-1].package && e.present_count==saved);
 uintptr_t c_edges=packages[c-1].uses;
 assert(!native_ct_unuse_package(&e,c,a) && e.error==NATIVE_CT_CAPACITY);
 assert(packages[c-1].uses==c_edges);e.error=0;e.present_capacity=3000;
 uintptr_t saved_names=e.name_count,saved_symbols=e.symbol_count,saved_present=e.present_count;
 assert(!native_ct_import_symbol(&e,0,ax) && e.error==NATIVE_CT_REFERENCE);e.error=0;
 assert(!native_ct_shadowing_import(&e,d,UINTPTR_MAX) && e.error==NATIVE_CT_REFERENCE);e.error=0;
 assert(!native_ct_use_package(&e,d,UINTPTR_MAX) && e.error==NATIVE_CT_REFERENCE);e.error=0;
 assert(e.name_count==saved_names && e.symbol_count==saved_symbols && e.present_count==saved_present);
 puts("native package transactions validate visibility before committing");
}
