#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct native_driver *compile(const char *source, unsigned target,
                                     unsigned level, unsigned profile) {
    struct native_driver *driver=calloc(1,sizeof *driver);
    assert(driver);
    driver->length=strlen(source);
    driver->source=malloc(driver->length+1);
    assert(driver->source);
    memcpy(driver->source,source,driver->length+1);
    assert(native_prepare_driver(driver));
    driver->context.target=target;
    driver->context.optimization=level;
    driver->context.profile=profile;
    struct native_unit_result result={0};
    assert(native_compile_unit(&driver->context,&driver->object,&result));
    return driver;
}

static void rejects_without_output(struct native_driver *driver, uintptr_t root,
                                    uint32_t stages) {
    uint8_t bytes[128],expected[128];
    memset(bytes,0xa5,sizeof bytes);
    memcpy(expected,bytes,sizeof bytes);
    struct byte_buffer output={bytes,7,sizeof bytes};
    struct native_ir_dump dump={.output=&output,.stages=stages};
    assert(!native_ir_dump_function(&driver->context,root,&dump));
    assert(dump.error==1 && output.length==7);
    assert(!memcmp(bytes,expected,sizeof bytes));
}

static void check(unsigned target,unsigned level,unsigned profile) {
    const char *source="(defun inspect (x p) (declare (type u64 x) "
        "(type (ptr u64) p) (returns u64) (c-export :c)) "
        "(let ((answer (if (= x 0) 18446744073709551615 (deref p)))) "
        "(store p answer) answer))";
    struct native_driver *driver=compile(source,target,level,profile);
    uintptr_t root=driver->hir.count;
    struct byte_buffer output={0};
    struct native_ir_dump dump={.output=&output,.stages=7};
    assert(!native_ir_dump_function(&driver->context,root,&dump));
    assert(dump.error==2 && dump.required>100 && !output.length);
    uintptr_t required=dump.required;
    uint8_t *bytes=malloc(required+2),*repeat=malloc(required+2);
    assert(bytes && repeat);
    memset(bytes,0xa5,required+2);
    output.data=bytes+1;output.capacity=required-1;
    assert(!native_ir_dump_function(&driver->context,root,&dump));
    assert(dump.error==2 && dump.required==required && !output.length);
    for(uintptr_t i=0;i<required+2;++i) assert(bytes[i]==0xa5);
    output.capacity=required;
    assert(native_ir_dump_function(&driver->context,root,&dump));
    assert(!dump.error && output.length==required && dump.required==required);
    assert(bytes[0]==0xa5 && bytes[required+1]==0xa5);
    memcpy(repeat,bytes+1,required);repeat[required]=0;
    assert(strstr((char *)repeat,"HIR inspect\n"));
    assert(strstr((char *)repeat,"SSA inspect\n"));
    assert(strstr((char *)repeat,"LIR inspect\n"));
    assert(strstr((char *)repeat,"18446744073709551615"));
    assert(strstr((char *)repeat,"PHI :U64"));
    assert(strstr((char *)repeat,"STORE :U64") || strstr((char *)repeat,"STORE :VOID"));
    assert(strstr((char *)repeat,"LOAD :U64"));
    assert(strstr((char *)repeat,"BRANCH"));
    output.length=0;
    assert(native_ir_dump_function(&driver->context,root,&dump));
    assert(output.length==required && !memcmp(repeat,bytes+1,required));
    /* The caller can select a stage and append without altering its prefix. */
    memcpy(bytes+1,"prefix\n",7);output.length=7;dump.stages=2;
    assert(native_ir_dump_function(&driver->context,root,&dump));
    assert(!memcmp(bytes+1,"prefix\nSSA inspect\n",19));
    assert(output.length<required);
    struct byte_buffer overflow={NULL,UINTPTR_MAX,UINTPTR_MAX};
    struct native_ir_dump too_long={.output=&overflow,.stages=7};
    assert(!native_ir_dump_function(&driver->context,root,&too_long));
    assert(too_long.error==3 && too_long.required==UINTPTR_MAX);
    assert(overflow.length==UINTPTR_MAX);
    rejects_without_output(driver,root,0);
    rejects_without_output(driver,root,8);
    rejects_without_output(driver,0,1);
    uint32_t kind=driver->hir.nodes[root-1].kind;
    driver->hir.nodes[root-1].kind=999;
    rejects_without_output(driver,root,1);
    driver->hir.nodes[root-1].kind=kind;
    kind=driver->ssa.values[0].kind;driver->ssa.values[0].kind=999;
    rejects_without_output(driver,root,2);driver->ssa.values[0].kind=kind;
    kind=driver->lir.instructions[0].kind;driver->lir.instructions[0].kind=999;
    rejects_without_output(driver,root,4);driver->lir.instructions[0].kind=kind;
    struct native_compile_context empty={0};
    assert(!native_ir_dump_function(&empty,root,&dump));
    assert(!native_ir_dump_function(NULL,root,&dump));
    assert(!native_ir_dump_function(&driver->context,root,NULL));
    free(bytes);free(repeat);native_release_driver(driver);free(driver);
}
int main(void) {
    for(unsigned target=0;target<4;++target)
        for(unsigned level=0;level<2;++level)
            for(unsigned profile=0;profile<2;++profile) check(target,level,profile);
    puts("native HIR/SSA/LIR text, exact unsigned values, stage selection, append, capacity and validation passed");
}
