#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static struct native_driver *prepare(const char *source,unsigned profile) {
 struct native_driver *d=calloc(1,sizeof*d);assert(d);d->length=strlen(source);
 d->source=malloc(d->length+1);assert(d->source);memcpy(d->source,source,d->length+1);
 assert(native_prepare_driver(d));d->context.profile=profile;return d;
}
static void check(const char *source,unsigned profile,unsigned phase,uint64_t modules) {
 struct native_driver *d=prepare(source,profile);struct native_unit_result r={0};
 int ok=native_compile_unit(&d->context,&d->object,&r);
 if(ok!=(phase==0)||r.phase!=phase||d->context.runtime_modules!=modules) {
  fprintf(stderr,"phase %zu expected %u status %d modules %llu expected %llu: %s\n",(size_t)r.phase,phase,ok,(unsigned long long)d->context.runtime_modules,(unsigned long long)modules,source);abort();
 }
 native_release_driver(d);free(d);
}
int main(void) {
 check("(defun f () (declare (returns value)) (make-byte-string 7 255))",1,0,900);
 check("(defun f (s) (declare (type value s) (returns u8)) (string-byte s 0))",1,0,900);
 check("(defun f (s) (declare (type value s) (returns void)) (without-allocation (set-string-byte s 0 255)))",1,0,900);
 check("(defun f () (declare (returns value)) (without-allocation (make-byte-string 7 255)))",1,9,0);
 check("(defun f () (declare (returns value)) (make-byte-string 7 255))",0,5,0);
 check("(defun f () (declare (returns value)) (make-byte-string 7 256))",1,6,0);
 check("(defun f () (declare (returns value)) (make-byte-string 7 -1))",1,6,0);
 check("(ffi:export-data \"psl_rt_make_string_precise\" u64 0)",1,11,0);
 struct native_driver *d=prepare("(defun f (s) (declare (type value s) (returns u8)) (string-byte s 0))",1);
 struct native_unit_result r={0};assert(native_compile_unit(&d->context,&d->object,&r));
 assert(lir_verify_function(&d->context));
 for(uintptr_t i=0;i<d->signature_context.signature_count;++i) {
  struct native_signature *sig=&d->storage.signatures[i];
  if(sig->runtime_id==11) {
   struct native_parameter *fill=&d->storage.parameters[sig->first_parameter+1];
   assert(fill->size==1 && fill->scalar_code==3);fill->size=8;
   assert(!native_runtime_signature_p(&d->context,sig));fill->size=1;
   assert(native_runtime_signature_p(&d->context,sig));
  }
  if(sig->runtime_id==12) {
   assert(sig->result_size==1 && sig->result_code==3);
   sig->result_size=8;assert(!lir_verify_function(&d->context));sig->result_size=1;
   assert(lir_verify_function(&d->context));
  }
 }
 native_release_driver(d);free(d);puts("Native string profiles, effects, module closure, byte ABI and receiver checks passed");return 0;
}
