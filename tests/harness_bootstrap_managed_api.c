#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct native_driver *prepare(const char *source, unsigned profile) {
    struct native_driver *d = calloc(1, sizeof *d);
    assert(d);
    d->length = strlen(source);
    d->source = malloc(d->length + 1);
    assert(d->source);
    memcpy(d->source, source, d->length + 1);
    d->context.profile = 77;
    d->context.runtime_modules = UINT64_MAX;
    assert(native_prepare_driver(d));
    assert(!d->context.profile && !d->context.runtime_modules);
    d->context.profile = profile;
    return d;
}
static void check(const char *source, unsigned profile, unsigned phase, uint64_t modules) {
    struct native_driver *d = prepare(source, profile);
    struct native_unit_result result = {0};
    int status = native_compile_unit(&d->context, &d->object, &result);
    if ((status != (phase == 0)) || result.phase != phase) {
        fprintf(stderr, "profile=%u expected phase=%u actual=%zu status=%d source=%s\n",
                profile, phase, (size_t)result.phase, status, source);
        abort();
    }
    assert(d->context.runtime_modules == modules);
    native_release_driver(d); free(d);
}
static void receivers(void) {
    struct native_driver *d = prepare("(defun f (x) (declare (type value x) (returns u64)) (if x 1 2))", 1);
    struct native_unit_result result = {0};
    assert(native_compile_unit(&d->context, &d->object, &result));
    assert(lir_verify_function(&d->context));
    struct native_signature *truth = NULL;
    for (uintptr_t i = 0; i < d->signature_context.signature_count; ++i)
        if (d->storage.signatures[i].runtime_id == 10) truth = &d->storage.signatures[i];
    assert(truth && native_runtime_signature_p(&d->context, truth));
    truth->allocation_free = 0;
    assert(!native_runtime_signature_p(&d->context, truth));
    assert(!lir_verify_function(&d->context));
    truth->allocation_free = 1;
    assert(lir_verify_function(&d->context));
    struct native_lir_instruction *call = NULL;
    for (uintptr_t i = 0; i < d->lir.count; ++i)
        if (d->storage.lir[i].kind == 7) call = &d->storage.lir[i];
    assert(call);
    /* A word-truth operation would incorrectly make managed NIL true. */
    call->kind = 20;
    call->left = d->storage.types[call->left - 1].left;
    call->target = 0;
    assert(!lir_verify_function(&d->context));
    native_release_driver(d); free(d);
}
int main(void) {
    check("(defun f (x) (declare (type value x) (returns value)) x)", 1, 0, 0);
    check("(defun f (x) (declare (type value x) (returns u64)) (if x 1 2))", 1, 0, 1);
    check("(defun f (x) (declare (type value x) (returns value)) (car x))", 1, 0, 898);
    check("(defun f (x) (declare (type value x) (returns s64)) (unbox-fixnum (car x)))", 1, 0, 899);
    check("(defun f (x) (declare (type value x) (returns value)) x)", 0, 5, 0);
    check("(defun f (x) (declare (type u64 x) (returns u64)) x)", 2, 10, 0);
    check("(defun f () (declare (returns value)) (cons 1 nil))", 1, 6, 0);
    check("(ffi:import-function \"foreign_unknown\" ((x value)) -> void) (defun f (x) (declare (type value x) (returns value)) (ffi:call foreign_unknown x) x)", 1, 6, 0);
    check("(ffi:import-function \"foreign_safe\" ((x value)) -> value :no-allocation) (defun f (x) (declare (type value x) (returns value)) (ffi:call foreign_safe x))", 1, 0, 0);
    check("(defun psl_rt_eq (x) (declare (type u64 x) (returns u64)) x)", 1, 11, 0);
    check("(ffi:export-data \"psl_rt_eq\" u64 0)", 1, 11, 0);
    check("(defcstruct value (x u64))", 1, 1, 0);
    check("(defcstruct holder (x value))", 1, 1, 0);
    check("(defun f (x) (declare (type (ptr value) x) (returns u64)) 0)", 1, 3, 0);
    check("(defun f () (declare (returns value)) 4611686018427387904)", 1, 6, 0);
    check("(defun f () (declare (returns value)) -4611686018427387905)", 1, 6, 0);
    check("(defun f (x) (declare (type value x) (returns value)) (wrap+ x 1))", 1, 6, 0);
    check("(defun f (x) (declare (type value x) (returns u64)) (wrap-cast u64 x))", 1, 6, 0);
    check("(defun f () (declare (returns value)) (without-allocation (cons 1 nil)))", 1, 9, 0);
    check("(defun f (x) (declare (type value x) (returns value)) (without-allocation (car x)))", 1, 0, 898);
    check("(ffi:import-function \"external_gc\" () -> void) (defun callee () (declare (returns void)) (ffi:call external_gc)) (defun f (x) (declare (type value x) (returns value)) (callee) x)", 1, 6, 0);
    receivers();
    puts("Native managed profile, dependency, safety, and receiver checks passed");
    return 0;
}
