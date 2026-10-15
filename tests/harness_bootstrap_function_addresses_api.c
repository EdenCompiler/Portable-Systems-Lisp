#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
extern uintptr_t win64_function_prologue(struct byte_buffer *,uintptr_t,uintptr_t);
extern int win64_return(struct byte_buffer *,uintptr_t);
static void capacity(unsigned target) {
 uint8_t bytes[40];memset(bytes,0xa5,sizeof bytes);
 struct byte_buffer code={bytes,0,sizeof bytes};
 struct native_call_fixup items[2]={{0}};
 struct native_fixup_arena addresses={items,0,2,0};
 assert(!native_encode_function_address_return(99,&code,&addresses,1));
 assert(!native_encode_function_address_return(target,&code,&addresses,0));
 assert(!native_encode_function_address_return(target,NULL,&addresses,1));
 assert(!native_encode_function_address_return(target,&code,NULL,1));
 addresses.capacity=0;assert(!native_encode_function_address_return(target,&code,&addresses,1));
 assert(!code.length && !addresses.count && !addresses.error);
 addresses.capacity=2;
 code.capacity=7;assert(!native_encode_function_address_return(target,&code,&addresses,1));code.capacity=sizeof bytes;
 assert(!code.length && !addresses.count && !addresses.error);
 for(unsigned i=0;i<sizeof bytes;++i)assert(bytes[i]==0xa5);
}
static struct native_driver *prepare(unsigned target,unsigned level) {
 const char *source="(defun address_target () (declare (returns u64) (c-export :c)) 42)";
 struct native_driver *d=calloc(1,sizeof *d);assert(d);d->length=strlen(source);d->source=malloc(d->length+1);assert(d->source);
 memcpy(d->source,source,d->length+1);assert(native_prepare_driver(d));d->context.target=target;d->context.optimization=level;
 struct native_unit_result result={0};assert(native_compile_unit(&d->context,&d->object,&result));assert(!d->context.runtime_modules);
 return d;
}
static void grow(struct native_driver *d,int far) {
 if(!far)return;
 const size_t length=(1u<<20)+128,capacity=length+256;
 uint8_t *code=calloc(1,capacity);assert(code);memcpy(code,d->code.data,d->code.length);
 free(d->storage.code);d->storage.code=code;d->code.data=code;d->code.length=length;d->code.capacity=capacity;
 d->storage.functions[0].size=length;
 free(d->storage.object);d->storage.object=calloc(1,capacity+8192);assert(d->storage.object);
 d->object.data=d->storage.object;d->object.capacity=capacity+8192;
}
static void bad_patches(struct native_driver *d,struct native_fixup_arena *addresses) {
 uint8_t *saved=malloc(d->code.length);assert(saved);memcpy(saved,d->code.data,d->code.length);
 uintptr_t reference=addresses->items[1].target;
 addresses->items[1].target=UINTPTR_MAX;
 assert(!native_patch_function_addresses(d->context.target,&d->code,d->storage.functions,2,addresses));
 assert(!memcmp(saved,d->code.data,d->code.length));addresses->items[1].target=reference;
 uintptr_t anchor=addresses->items[0].instruction;addresses->items[0].instruction=UINTPTR_MAX;
 assert(!native_patch_function_addresses(d->context.target,&d->code,d->storage.functions,2,addresses));addresses->items[0].instruction=anchor;
 d->storage.functions[0].imported=1;
 assert(!native_patch_function_addresses(d->context.target,&d->code,d->storage.functions,2,addresses));d->storage.functions[0].imported=0;
 struct native_function interleaved[3];memset(interleaved,0,sizeof interleaved);
 interleaved[0]=d->storage.functions[0];interleaved[1].imported=1;
 interleaved[2]=d->storage.functions[1];addresses->items[0].target=3;
 assert(!native_patch_function_addresses(d->context.target,&d->code,interleaved,3,addresses));
 addresses->items[0].target=1;
 uint8_t first=d->code.data[anchor];d->code.data[anchor]=0;
 assert(!native_patch_function_addresses(d->context.target,&d->code,d->storage.functions,2,addresses));d->code.data[anchor]=first;
 assert(!memcmp(saved,d->code.data,d->code.length));free(saved);
}
static int write_object(struct native_driver *d) {
 d->object.length=0;
 if(d->context.target==NATIVE_TARGET_X86_64_WINDOWS)
  return write_coff64_calls(d->code.data,d->code.length,d->storage.functions,2,&d->calls,&d->object);
 return write_elf64_calls_target(d->context.target,d->code.data,d->code.length,d->storage.functions,2,&d->calls,&d->object);
}
int main(int argc,char **argv) {
 assert(argc==5);unsigned target=(unsigned)strtoul(argv[1],NULL,10),level=(unsigned)strtoul(argv[2],NULL,10);int far=atoi(argv[3]);
 assert(target<4 && level<2);capacity(target);struct native_driver *d=prepare(target,level);grow(d,far);
 struct native_call_fixup items[2]={{0}};struct native_fixup_arena addresses={items,0,2,0};
 uintptr_t start=d->code.length,frame=0,prologue=0;
 if(target==NATIVE_TARGET_X86_64_WINDOWS) {
  /* COFF carries the native backend's verified frame and unwind shape. */
  frame=112;prologue=win64_function_prologue(&d->code,frame,32);assert(prologue==11);
  assert(native_encode_function_address(target,&d->code,&addresses,1));
  assert(win64_return(&d->code,frame));
 } else assert(native_encode_function_address_return(target,&d->code,&addresses,1));
 uintptr_t end=d->code.length;
 d->storage.functions[1]=(struct native_function){(const uint8_t*)"address_probe",13,start,end-start,0,1,0,1,frame,prologue};
 /* Two records let the invalid final target prove all validation precedes any
    patch, and also exercise repeat patching of the same owned instruction. */
 addresses.items[1]=addresses.items[0];addresses.count=2;bad_patches(d,&addresses);
 assert(native_patch_function_addresses(target,&d->code,d->storage.functions,2,&addresses));
 uint8_t *saved=malloc(d->code.length);assert(saved);memcpy(saved,d->code.data,d->code.length);
 assert(native_patch_function_addresses(target,&d->code,d->storage.functions,2,&addresses));assert(!memcmp(saved,d->code.data,d->code.length));free(saved);
 assert(write_object(d));FILE *output=fopen(argv[4],"wb");assert(output);
 assert(fwrite(d->object.data,1,d->object.length,output)==d->object.length);assert(!fclose(output));
 native_release_driver(d);free(d);return 0;
}
