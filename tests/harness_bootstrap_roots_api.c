#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct native_driver *prepare(const char *source) {
 struct native_driver *d=calloc(1,sizeof *d);assert(d);
 d->length=strlen(source);d->source=malloc(d->length+1);assert(d->source);
 memcpy(d->source,source,d->length+1);assert(native_prepare_driver(d));
 assert(!d->lir.root_count);d->context.profile=1;return d;
}
static void capacity_and_receiver(void) {
 struct native_driver *d=prepare("(ffi:import-function \"root_gc\" () -> void) (defun f (x) (declare (type value x) (returns value)) (ffi:call root_gc) x)");
 uintptr_t capacity=d->lir.capacity;d->lir.capacity=4;
 struct native_unit_result result={0};assert(!native_compile_unit(&d->context,&d->object,&result));
 assert(result.phase==6 && d->lir.count==4 && !d->lir.root_count);
 assert(d->storage.lir[0].kind==100 && d->storage.lir[1].kind==7);
 d->lir.capacity=capacity;
 d->storage.lir[0].target=2;assert(!native_lower_roots(&d->context));assert(d->lir.count==4);
 d->storage.lir[0].target=1;
 ++d->context.current_arity;assert(!native_lower_roots(&d->context));--d->context.current_arity;
 struct native_lir_instruction original=d->storage.lir[1];
 d->storage.lir[1].kind=110;d->storage.lir[1].target=0;
 assert(!native_lower_roots(&d->context) && d->lir.count==4 && !d->lir.root_count);
 d->storage.lir[1]=original;
 for(uintptr_t i=0;i<d->signature_context.signature_count;++i) {
  struct native_signature *sig=&d->storage.signatures[i];
  if(sig->runtime_id==7 || sig->runtime_id==8) {
   uint8_t free=sig->allocation_free;sig->allocation_free=0;
   assert(!native_lower_roots(&d->context) && d->lir.count==4 && !d->lir.root_count);
   sig->allocation_free=free;
  }
 }
 assert(native_lower_roots(&d->context));assert(lir_verify_function(&d->context));
 assert(d->lir.root_count==2);uintptr_t count=d->lir.count;
 d->lir.root_count=0;
 assert(!native_lower_roots(&d->context) && d->lir.count==count && !d->lir.root_count);
 d->lir.root_count=2;
 assert(native_lower_roots(&d->context) && d->lir.count==count);
 --d->lir.root_count;assert(!lir_verify_function(&d->context));++d->lir.root_count;
 ++d->context.current_arity;assert(!lir_verify_function(&d->context));--d->context.current_arity;
 for(uintptr_t i=0;i<count;++i) {
  struct native_lir_instruction *op=&d->storage.lir[i];struct native_lir_instruction saved=*op;
  if(op->kind>=110 && op->kind<=113) {
   op->source=1;assert(!lir_verify_function(&d->context));*op=saved;
   op->scalar_code=15;assert(!lir_verify_function(&d->context));*op=saved;
  }
  if(op->kind==112) {op->kind=110;assert(!lir_verify_function(&d->context));*op=saved;}
  if(op->kind==113) {op->target=1;assert(!lir_verify_function(&d->context));*op=saved;}
  if(op->kind==111) {
   struct native_signature *push=&d->storage.signatures[op->target-1];uint32_t ready=push->effect_ready;
   push->effect_ready=0;assert(!lir_verify_function(&d->context));push->effect_ready=ready;
  }
 }
 assert(lir_verify_function(&d->context));assert(d->context.runtime_modules==0);
 native_release_driver(d);free(d);
}
static void catalogue(const char *source,uintptr_t roots,uint64_t modules) {
 struct native_driver *d=prepare(source);struct native_unit_result result={0};
 assert(native_compile_unit(&d->context,&d->object,&result));
 assert(lir_verify_function(&d->context));assert(d->lir.root_count==roots);
 assert(d->context.runtime_modules==modules);native_release_driver(d);free(d);
}
int main(void) {
 capacity_and_receiver();
 catalogue("(defun f (x) (declare (type value x) (returns u64)) (collect-garbage) 42)",1,896);
 catalogue("(defun f () (declare (returns u64)) (collect-garbage) 42)",0,896);
 catalogue("(defun f (x) (declare (type value x) (returns value)) (car x))",0,898);
 puts("Native root capacity, lazy parameter catalogue, lifetime and ABI receiver checks passed");
 return 0;
}
