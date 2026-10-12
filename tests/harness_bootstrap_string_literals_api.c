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
 check("(defun f () (declare (returns value)) \"hello\")",1,0,900);
 check("(defun f () (declare (returns value)) (without-allocation \"hello\"))",1,9,0);
 check("(defun f () (declare (returns value)) \"hello\")",0,5,0);
 check("(defun f () (declare (returns u64)) \"hello\")",1,6,0);
 check("(ffi:export-data \"psl_rt_make_string_from_bytes_precise\" u64 0)",1,11,0);
 const char *invalid[]={"\200","\300\200","\302","\340\237\277","\355\240\200","\360\217\277\277","\364\220\200\200","\365\200\200\200","\302\\\200"};
 for(size_t i=0;i<sizeof invalid/sizeof invalid[0];++i) {
  char source[128];snprintf(source,sizeof source,"(defun f () (declare (returns value)) \"%s\")",invalid[i]);
  check(source,1,6,0);
 }
 struct native_driver *d=prepare("(defun f () (declare (returns value)) \"hello\")",1);
 struct native_unit_result r={0};assert(native_compile_unit(&d->context,&d->object,&r));
 assert(lir_verify_function(&d->context));assert(ssa_verify_function(&d->context));
 assert(hir_verify_scalar_tree(&d->context,d->hir.count,0));
 struct native_data_import *data=&d->storage.data_imports[d->context.data_count-1];
 assert(data->literal==1 && data->size==6 && !memcmp(data->bytes,"hello",6));
 data->literal=0;assert(!hir_verify_scalar_tree(&d->context,d->hir.count,0));assert(!lir_verify_function(&d->context));assert(!ssa_verify_function(&d->context));data->literal=1;
 data->type_ast=1;assert(!lir_verify_function(&d->context));data->type_ast=0;
 data->global=1;assert(!lir_verify_function(&d->context));data->global=0;
 data->defined=0;assert(!lir_verify_function(&d->context));data->defined=1;
 data->alignment=8;assert(!lir_verify_function(&d->context));data->alignment=1;
 const uint8_t *bytes=data->bytes;data->bytes=d->context.data_bytes+d->context.data_byte_count;
 assert(!lir_verify_function(&d->context));data->bytes=bytes;
 uintptr_t used=d->context.data_byte_count;d->context.data_byte_count=0;
 assert(!lir_verify_function(&d->context));d->context.data_byte_count=used;
 data->size=0;assert(!lir_verify_function(&d->context));data->size=6;
 for(uintptr_t i=0;i<d->hir.count;++i) {
  struct native_hir_node *node=&d->hir.nodes[i];
  if(node->kind==1 && node->scalar_code==2 && node->value==5) {
   node->value=6;assert(!hir_verify_scalar_tree(&d->context,d->hir.count,0));node->value=5;
  }
 }
 for(uintptr_t i=0;i<d->lir.count;++i) {
  struct native_lir_instruction *op=&d->lir.instructions[i];
  if(op->kind==35) {
   op->scalar_code=11;assert(!lir_verify_function(&d->context));op->scalar_code=1;
  }
  if(op->kind==1 && op->scalar_code==2 && op->value==5) {
   op->value=6;assert(!lir_verify_function(&d->context));op->value=5;
  }
 }
 for(uintptr_t i=0;i<d->ssa.value_count;++i) {
  struct native_ssa_value *op=&d->ssa.values[i];
  if(op->kind==1 && op->scalar_code==2 && op->value==5) {
   op->value=6;assert(!ssa_verify_function(&d->context));op->value=5;
  }
 }
 assert(lir_verify_function(&d->context));assert(ssa_verify_function(&d->context));
 assert(hir_verify_scalar_tree(&d->context,d->hir.count,0));
 native_release_driver(d);free(d);
 for(unsigned mode=0;mode<2;++mode) {
  d=prepare("(defun f () (declare (returns value)) \"hello\")",1);
  if(mode) d->context.data_byte_capacity=5;else d->context.data_capacity=0;
  memset(&r,0,sizeof r);assert(!native_compile_unit(&d->context,&d->object,&r));
  assert(r.phase==(mode?3:6) && d->context.data_count==0 && d->context.data_byte_count==0);
  native_release_driver(d);free(d);
 }
 puts("Native literal profiles, effects, extent and receiver checks passed");return 0;
}
