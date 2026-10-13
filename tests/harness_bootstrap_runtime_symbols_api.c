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
 check("(defun f (name) (declare (type value name) (returns value)) (make-symbol name))",1,0,908);
 check("(defun f (s) (declare (type value s) (returns value)) (without-allocation (symbol-name s)))",1,0,908);
 check("(defun f (name) (declare (type value name) (returns value)) (make-package-from-name name))",1,0,924);
 check("(defun f (p) (declare (type value p) (returns value)) (without-allocation (package-name p)))",1,0,924);
 check("(defun f (p name) (declare (type value p name) (returns value)) (intern-symbol p name))",1,0,924);
 check("(defun f () (declare (returns value)) (without-allocation (make-symbol \"Name\")))",1,9,0);
 check("(defun f (name) (declare (type value name) (returns value)) (without-allocation (make-package-from-name name)))",1,9,0);
 check("(defun f (p name) (declare (type value p name) (returns value)) (without-allocation (intern-symbol p name)))",1,9,0);
 check("(defun f () (declare (returns value)) (make-symbol \"Name\"))",0,5,0);
 check("(ffi:export-data \"psl_rt_make_symbol_precise\" u64 0)",1,11,0);
 check("(ffi:export-data \"psl_rt_make_package_precise\" u64 0)",1,11,0);
 check("(ffi:export-data \"psl_rt_intern_precise\" u64 0)",1,11,0);
 check("(defpackage \"LOCAL-SYMBOLS\" (:use \"COMMON-LISP\") (:import-from \"PSL\" \"U64\" \"RETURNS\" \"WRAP+\") (:shadow \"MAKE-SYMBOL\")) (in-package \"LOCAL-SYMBOLS\") (defun make-symbol (x) (declare (type u64 x) (returns u64)) (wrap+ x 1)) (defun f () (declare (returns u64)) (make-symbol 41))",1,0,0);
 struct native_driver *d=prepare("(defun f (name) (declare (type value name) (returns value)) (make-symbol name))",1);
 struct native_unit_result r={0};assert(native_compile_unit(&d->context,&d->object,&r));
 assert(lir_verify_function(&d->context));
 unsigned seen=0;
 for(uintptr_t i=0;i<d->signature_context.signature_count;++i) {
  struct native_signature *sig=&d->signature_context.signatures[i];
  if(sig->runtime_id>=15 && sig->runtime_id<=19) {
   ++seen;assert(native_runtime_signature_p(&d->context,sig));
   assert(sig->arity==(sig->runtime_id==19?2:1));
   assert(sig->result_code==15 && sig->result_size==8);
   assert(sig->allocation_free==(sig->runtime_id==16 || sig->runtime_id==18));
   struct native_parameter *param=&d->signature_context.parameters[sig->first_parameter];
   assert(param->scalar_code==15 && param->size==8);param->scalar_code=1;
   assert(!native_runtime_signature_p(&d->context,sig));param->scalar_code=15;
   uint8_t effect=sig->allocation_free;sig->allocation_free=!effect;
   assert(!native_runtime_signature_p(&d->context,sig));sig->allocation_free=effect;
   assert(native_runtime_signature_p(&d->context,sig));
  }
 }
 assert(seen==5 && lir_verify_function(&d->context));
 native_release_driver(d);free(d);puts("Native symbol/package profiles, effects, dependencies and receiver checks passed");return 0;
}
