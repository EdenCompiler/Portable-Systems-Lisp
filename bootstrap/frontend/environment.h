#ifndef PSL_NATIVE_ENVIRONMENT_H
#define PSL_NATIVE_ENVIRONMENT_H

/* Caller-owned build-host compiler tables. Names are exact decoded bytes;
   table references are one-based IDs, with zero denoting absence. Initialize
   the record and arenas to zero. Mutations latch the first error; clear it
   explicitly before retrying. Low-level bind/link helpers construct visibility
   and do not implement Common Lisp package transactions. */
#include <stddef.h>
#include <stdint.h>
enum native_ct_error {
    NATIVE_CT_CAPACITY = 1,
    NATIVE_CT_DUPLICATE = 2,
    NATIVE_CT_CONFLICT = 3,
    NATIVE_CT_REFERENCE = 4,
    NATIVE_CT_PACKAGE = 6,
    NATIVE_CT_TOKEN = 8,
    NATIVE_CT_EXTERNAL = 9
};
struct native_ct_package { uintptr_t name,length,present,uses; };
struct native_ct_symbol { uintptr_t package,name,length; };
struct native_ct_presence { uintptr_t symbol,next; uint32_t flags; };
struct native_ct_use { uintptr_t package,next; };
struct native_ct_alias { uintptr_t package,name,length; };
struct native_ct_environment {
    uint8_t *names; uintptr_t name_count,name_capacity;
    struct native_ct_package *packages; uintptr_t package_count,package_capacity;
    struct native_ct_symbol *symbols; uintptr_t symbol_count,symbol_capacity;
    struct native_ct_presence *present; uintptr_t present_count,present_capacity;
    struct native_ct_use *uses; uintptr_t use_count,use_capacity;
    struct native_ct_alias *aliases; uintptr_t alias_count,alias_capacity;
    uintptr_t current_package,keyword_package,nil_symbol,true_symbol;
    uintptr_t name_cursor; int32_t name_result;
    uintptr_t lookup_cursor,lookup_result;
    uintptr_t read_cursor,read_prefix,read_separator; uint32_t read_separators;
    uint8_t read_bar,read_escape,read_body,read_uninterned; uint32_t error;
};
extern uintptr_t native_ct_make_package(struct native_ct_environment *,const uint8_t *,uintptr_t);
extern uintptr_t native_ct_find_package(struct native_ct_environment *,const uint8_t *,uintptr_t);
extern uintptr_t native_ct_find_symbol(struct native_ct_environment *,uintptr_t,const uint8_t *,uintptr_t);
extern uintptr_t native_ct_intern(struct native_ct_environment *,uintptr_t,const uint8_t *,uintptr_t);
extern uintptr_t native_ct_bind_symbol(struct native_ct_environment *,uintptr_t,uintptr_t,uint32_t);
extern int native_ct_link_use(struct native_ct_environment *,uintptr_t,uintptr_t);
extern uintptr_t native_ct_add_alias(struct native_ct_environment *,uintptr_t,const uint8_t *,uintptr_t);
extern int native_ct_seed_standard(struct native_ct_environment *);
extern uintptr_t native_ct_read_symbol(struct native_ct_environment *,const uint8_t *,uintptr_t);

#endif
