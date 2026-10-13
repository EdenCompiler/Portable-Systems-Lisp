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
 check("(defun f () (declare (returns value)) (values 19 23))",1,0,960);
 check("(defun f () (declare (returns value)) (multiple-value-bind (a b) (values 19 23) b))",1,0,960);
 check("(defun f () (declare (returns value)) (multiple-value-bind (a b) (values 19 23) (without-allocation b)))",1,0,960);
 check("(defun f () (declare (returns value)) (without-allocation (values 19 23)))",1,9,0);
 check("(defun f () (declare (returns value)) (without-allocation (multiple-value-bind (a b) (values 19 23) b)))",1,9,0);
 check("(defun f () (declare (returns value)) (values 19 23))",0,5,0);
 check("(defun f () (declare (returns u64)) (values 19 23))",1,6,0);
 const char *invalid[]={"(values)","(values 1)","(values 1 2 3)",
  "(multiple-value-bind (a b c) (values 1 2) b)",
  "(multiple-value-bind (a a) (values 1 2) a)",
  "(multiple-value-bind (:a b) (values 1 2) b)",
  "(multiple-value-bind (nil b) (values 1 2) b)",
  "(multiple-value-bind (t b) (values 1 2) b)",
  "(multiple-value-bind (a b) (cons 1 nil) b)",
  "(multiple-value-bind (a b) (values 1 2))"};
 for(size_t i=0;i<sizeof invalid/sizeof invalid[0];++i) {
  char source[256];snprintf(source,sizeof source,"(defun f () (declare (returns value)) %s)",invalid[i]);
  check(source,1,6,0);
 }
 check("(ffi:export-data \"psl_rt_values2\" u64 0)",1,11,0);
 check("(ffi:export-data \"psl_rt_nth_value\" u64 0)",1,11,0);
 struct native_driver *d=prepare("(defun f () (declare (returns value)) (multiple-value-bind (a b) (values 19 23) b))",1);
 struct native_unit_result r={0};assert(native_compile_unit(&d->context,&d->object,&r));
 assert(lir_verify_function(&d->context));unsigned seen=0;
 for(uintptr_t i=0;i<d->signature_context.signature_count;++i) {
  struct native_signature *sig=&d->signature_context.signatures[i];
  if(sig->runtime_id==20 || sig->runtime_id==21) {
   ++seen;assert(native_runtime_signature_p(&d->context,sig));
   assert(sig->result_code==15 && sig->result_size==8);
   assert(sig->arity==(sig->runtime_id==20?2:1));
   assert(sig->allocation_free==(sig->runtime_id==21));
   uint8_t effect=sig->allocation_free;sig->allocation_free=!effect;
   assert(!lir_verify_function(&d->context));sig->allocation_free=effect;
   assert(lir_verify_function(&d->context));
  }
 }
 assert(seen==2);native_release_driver(d);free(d);
 puts("Native two-value profiles, effects, names, shape and ABI receivers passed");return 0;
}
