#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct native_driver *prepare(const char *source,unsigned level,
                                     unsigned target,unsigned profile) {
    struct native_driver *driver=calloc(1,sizeof *driver);
    assert(driver);
    driver->length=strlen(source);
    driver->source=malloc(driver->length+1);
    assert(driver->source);
    memcpy(driver->source,source,driver->length+1);
    assert(native_prepare_driver(driver));
    driver->context.optimization=level;
    driver->context.target=target;
    driver->context.profile=profile;
    return driver;
}
static void release(struct native_driver *driver) {
    native_release_driver(driver);
    free(driver);
}
static void check(const char *source,unsigned level,unsigned target,unsigned profile) {
    struct native_driver *plain=prepare(source,level,target,profile);
    struct native_driver *observed=prepare(source,level,target,profile);
    struct native_unit_result result={0};
    uint8_t text[32768];
    struct byte_buffer output={text,7,sizeof text-1};
    memcpy(text,"prefix\n",7);
    struct native_ir_dump dump={.output=&output,.stages=7};
    observed->context.ir_dump=&dump;
    assert(native_compile_unit(&plain->context,&plain->object,&result));
    result=(struct native_unit_result){0};
    assert(native_compile_unit(&observed->context,&observed->object,&result));
    assert(plain->object.length==observed->object.length);
    assert(!memcmp(plain->object.data,observed->object.data,plain->object.length));
    assert(output.length>7 && output.length<sizeof text);
    text[output.length]=0;
    assert(!memcmp(text,"prefix\n",7));
    const char *first=strstr((char *)text,"HIR first\n");
    const char *second=strstr((char *)text,"HIR second\n");
    assert(first && second && first<second);
    assert(!strstr(first+1,"HIR first\n") && !strstr(second+1,"HIR second\n"));
    assert(strstr((char *)text,"SSA first\n") && strstr((char *)text,"LIR first\n"));
    assert(strstr((char *)text,"SSA second\n") && strstr((char *)text,"LIR second\n"));
    if(profile) {
        assert(strstr((char *)text,"ROOT-PUSH"));
        assert(strstr((char *)text,"ROOT-POP"));
        assert(strstr((char *)text," :VALUE"));
    }
    release(plain);release(observed);
    /* A capture capacity failure prevents native object publication. */
    observed=prepare(source,level,target,profile);
    memset(text,0xa5,sizeof text);
    output=(struct byte_buffer){text,0,1};
    dump=(struct native_ir_dump){.output=&output,.stages=7};
    observed->context.ir_dump=&dump;
    result=(struct native_unit_result){0};
    assert(!native_compile_unit(&observed->context,&observed->object,&result));
    assert(result.phase==NATIVE_UNIT_BODY && observed->object.length==0);
    assert(dump.error==2 && dump.required>1 && !output.length);
    for(unsigned i=0;i<sizeof text;++i) assert(text[i]==0xa5);
    release(observed);
}
int main(void) {
    const char *typed="(defun first (x) (declare (type u64 x) (returns u64)) (wrap+ x 1))"
        "(defun second (x) (declare (type u64 x) (returns u64)) (first x))";
    const char *managed="(defun first (x) (declare (type value x) (returns value)) x)"
        "(defun second (x) (declare (type value x) (returns value)) (cons (first x) nil))";
    for(unsigned level=0;level<2;++level)for(unsigned target=0;target<4;++target) {
        check(typed,level,target,0);check(managed,level,target,1);
    }
    puts("whole-unit verified IR capture preserves object bytes, source order, roots and failed-output ownership");
}
