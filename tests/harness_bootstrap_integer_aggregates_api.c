#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static struct native_driver *prepare(const char *source,unsigned target,unsigned profile,unsigned level) {
 struct native_driver *d=calloc(1,sizeof *d); assert(d);
 d->length=strlen(source); d->source=malloc(d->length+1); assert(d->source);
 memcpy(d->source,source,d->length+1); assert(native_prepare_driver(d));
 d->context.target=target; d->context.profile=profile; d->context.optimization=level; return d;
}
static void release(struct native_driver *d) { native_release_driver(d); free(d); }
static void check(const char *source,unsigned target,unsigned profile,unsigned level,int expected) {
 struct native_driver *d=prepare(source,target,profile,level); struct native_unit_result r={0};
 int ok=native_compile_unit(&d->context,&d->object,&r);
 if(ok!=expected) { fprintf(stderr,"aggregate acceptance %d expected %d phase %zu target %u profile %u O%u: %s\n",ok,expected,(size_t)r.phase,target,profile,level,source); abort(); }
 assert(expected?d->object.length>0:d->object.length==0);
 assert(d->context.runtime_modules==0); release(d);
}
static void receiver_rejects(struct native_driver *d) {
 assert(!hir_verify_scalar_tree(&d->context,d->hir.count,0));
 assert(!ssa_verify_function(&d->context));
 assert(!lir_verify_function(&d->context));
}
static void receivers_accept(struct native_driver *d) {
 assert(hir_verify_scalar_tree(&d->context,d->hir.count,0));
 assert(ssa_verify_function(&d->context)); assert(lir_verify_function(&d->context));
}
static void check_output_capacity(unsigned target,unsigned level,int object) {
 const char *source="(defcstruct r (x u64) (y u64))"
 "(ffi:import-function \"copy\" ((x r)) -> r :no-allocation)"
 "(defun f (x) (declare (type r x) (returns r)) (ffi:call copy x))";
 struct native_driver *d=prepare(source,target,0,level);
 struct byte_buffer *buffer=object?&d->object:&d->code;
 uintptr_t capacity=buffer->capacity;
 assert(capacity>=16); memset(buffer->data,0xa5,16); buffer->capacity=1;
 struct native_unit_result r={0};
 assert(!native_compile_unit(&d->context,&d->object,&r));
 assert(r.phase==(object?NATIVE_UNIT_OBJECT:NATIVE_UNIT_BODY));
 assert(d->object.length==0 && buffer->length<=buffer->capacity);
 for(unsigned i=1;i<16;++i) assert(buffer->data[i]==0xa5);
 buffer->capacity=capacity; release(d);
}
static void check_receivers(unsigned target,unsigned level) {
 const char *source="(defcstruct record (x u64) (y u64)) (defcstruct other (x u64) (y u64))"
 "(defun f (x) (declare (type record x) (returns record)) x)";
 struct native_driver *d=prepare(source,target,0,level); struct native_unit_result r={0};
 assert(native_compile_unit(&d->context,&d->object,&r)); receivers_accept(d);
 assert(d->hir.count==1 && d->hir.nodes[0].scalar_code==16);
 struct native_layout *layout=d->layouts.layouts;
 struct native_layout_field *field=d->layouts.fields;
 layout->packed=1; receiver_rejects(d); layout->packed=0;
 uintptr_t saved=layout->size; layout->size=8; receiver_rejects(d); layout->size=saved;
 saved=layout->alignment; layout->alignment=1; receiver_rejects(d); layout->alignment=saved;
 saved=layout->count; layout->count=d->layouts.field_count+1; receiver_rejects(d); layout->count=saved;
 saved=layout->first; layout->first=UINTPTR_MAX; receiver_rejects(d); layout->first=saved;
 saved=field->size; field->size=2; receiver_rejects(d); field->size=saved;
 saved=field->alignment; field->alignment=1; receiver_rejects(d); field->alignment=saved;
 saved=field->offset; field->offset=1; receiver_rejects(d); field->offset=saved;
 saved=field->type_ast; field->type_ast=UINTPTR_MAX; receiver_rejects(d); field->type_ast=saved;
 receivers_accept(d);
 uintptr_t reference=d->hir.nodes[0].pointee;
 uintptr_t invalid[]={0,UINTPTR_MAX,reference|UINT64_C(0x4000000000000000),d->layouts.layouts[1].name};
 for(unsigned i=0;i<sizeof invalid/sizeof invalid[0];++i) {
  d->hir.nodes[0].pointee=invalid[i];
  assert(!hir_verify_scalar_tree(&d->context,1,0)); d->hir.nodes[0].pointee=reference;
  d->ssa.values[0].pointee=d->lir.types[0].pointee=invalid[i];
  assert(!ssa_verify_function(&d->context)); d->ssa.values[0].pointee=d->lir.types[0].pointee=reference;
  /* Change the instruction and receiving catalogue together, so rejecting it
     requires source type validation rather than only duplicate-field checks. */
  for(uintptr_t j=0;j<d->lir.count;++j) if(d->lir.instructions[j].scalar_code==16) d->lir.instructions[j].pointee=invalid[i];
  d->lir.types[0].pointee=invalid[i]; assert(!lir_verify_function(&d->context));
  for(uintptr_t j=0;j<d->lir.count;++j) if(d->lir.instructions[j].scalar_code==16) d->lir.instructions[j].pointee=reference;
  d->lir.types[0].pointee=reference; receivers_accept(d);
 }
 release(d);
}
int main(void) {
 static const char *accepted[]={
 "(defcstruct r (x f64)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (a u8) (b u8) (c u8)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (x u64) (y u64)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (x u8)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (a s8) (b u8)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct inner (x u16)) (defcstruct r (a inner) (b u16)) (defun f (x) (declare (type r x) (returns r)) (let ((a x)) a))",
 "(defcstruct r (p (ptr void))) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct inner (a u16) (b u8)) (defcstruct r (first inner) (middle u32) (last u64)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (a (ptr u8 :const)) (b (ptr (ptr u8 :volatile)))) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defpackage :agg-a (:use :cl) (:import-from :psl :defcstruct :u64)) (in-package :agg-a) (defcstruct record (a u64) (b u64)) (defpackage :agg-main (:use :cl)) (in-package :agg-main) (defun f (x) (declare (type agg-a::record x) (psl:returns agg-a::record)) x)",
 "(defcstruct r (x c-long)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (x u32)) (defun f (p x) (declare (type (ptr r :const) p) (type r x) (returns u32)) (if (= 0 0) (deref (field-pointer p 'x)) 42))",
 "(defcstruct r (x u32)) (defun f (x) (declare (type r x) (returns u64)) (if x 42 0))",
 "(defcstruct r (x u32)) (ffi:import-function \"safe\" ((x r)) -> r :no-allocation) (defun f (x) (declare (type r x) (returns r)) (without-allocation (ffi:call safe x)))"
 };
 static const char *rejected[]={
 "(defcstruct r (x u64) (y u64) (z u64)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defstruct/packed r (x u32)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defstruct/packed inner (x u8)) (defcstruct r (x inner)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (x u32)) (defcstruct s (x u32)) (defun f (x) (declare (type r x) (returns s)) x)",
 "(defpackage :agg-a (:use :cl) (:import-from :psl :defcstruct :u64)) (defpackage :agg-b (:use :cl) (:import-from :psl :defcstruct :u64)) (in-package :agg-a) (defcstruct record (a u64) (b u64)) (in-package :agg-b) (defcstruct record (a u64) (b u64)) (defpackage :agg-main (:use :cl)) (in-package :agg-main) (defun f (x) (declare (type agg-a::record x) (psl:returns agg-b::record)) x)",
 "(defcstruct r (x u32)) (defcstruct s (x u32)) (ffi:import-function \"foreign\" ((x s)) -> r) (defun f (x) (declare (type r x) (returns r)) (ffi:call foreign x))",
 "(defcstruct r (x u32)) (defcstruct s (x u32)) (defun f (p x) (declare (type (ptr r) p) (type s x) (returns r)) (store p x))",
 "(defcstruct r (x u32)) (defun f (p) (declare (type (ptr r) p) (returns r)) (deref p))",
 "(defcstruct r (x u32)) (defun f (p x) (declare (type (ptr r) p) (type r x) (returns r)) (store p x))",
 "(defcstruct r (x u32)) (defun f () (declare (returns r)) 0)",
 "(defcstruct r (x u32)) (defun f (x) (declare (type r x) (returns r)) (wrap+ x x))",
 "(defcstruct r (x u32)) (defun f (x) (declare (type r x) (returns u64)) (wrap-cast u64 x))",
 "(defcstruct r (x u32)) (defun f (x) (declare (type r x) (returns u64)) (if (= x x) 1 0))",
 "(defcstruct r (x u32)) (defun f (p x) (declare (type (ptr r :const) p) (type r x) (returns r)) (store p x))",
 "(defcstruct r (x u32)) (defun f (x) (declare (type r x) (returns (ptr u32))) (ptr-cast r x))",
 "(defcstruct r (x value)) (defun f (x) (declare (type r x) (returns r)) x)",
 "(defcstruct r (x u32)) (ffi:import-function \"unsafe\" ((x r)) -> r) (defun f (x) (declare (type r x) (returns r)) (without-allocation (ffi:call unsafe x)))"
 };
 for(unsigned level=0;level<2;++level) for(unsigned target=0;target<4;++target) {
  for(unsigned profile=0;profile<2;++profile) {
   for(unsigned i=0;i<sizeof accepted/sizeof accepted[0];++i) check(accepted[i],target,profile,level,1);
   for(unsigned i=0;i<sizeof rejected/sizeof rejected[0];++i) check(rejected[i],target,profile,level,0);
  }
  check_receivers(target,level);
  check_output_capacity(target,level,0); check_output_capacity(target,level,1);
 }
 puts("native large aggregate profiles, shape identity, effects and HIR/SSA/LIR receiver checks passed");
}
