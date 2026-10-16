#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct native_driver *prepare(const char *source, unsigned profile) {
    struct native_driver *driver = calloc(1, sizeof *driver);
    assert(driver);
    driver->length = strlen(source);
    driver->source = malloc(driver->length + 1);
    assert(driver->source);
    memcpy(driver->source, source, driver->length + 1);
    assert(native_prepare_driver(driver));
    driver->context.profile = profile;
    return driver;
}

static void release(struct native_driver *driver) {
    native_release_driver(driver);
    free(driver);
}

static void check(const char *source, unsigned profile, unsigned phase,
                  uint64_t modules, unsigned optimize) {
    struct native_driver *driver = prepare(source, profile);
    struct native_unit_result result = {0};
    driver->context.optimization = optimize;
    int ok = native_compile_unit(&driver->context, &driver->object, &result);
    if (ok != (phase == 0) || result.phase != phase ||
        driver->context.runtime_modules != modules) {
        fprintf(stderr, "phase %zu/%u ok %d modules %llu/%llu: %s\n",
                (size_t)result.phase, phase, ok,
                (unsigned long long)driver->context.runtime_modules,
                (unsigned long long)modules, source);
        abort();
    }
    release(driver);
}

static void check_receivers(unsigned optimize) {
    struct native_driver *driver = prepare(
        "(defun f (v i) (declare (type value v) (type usize i)"
        " (returns value)) (value-vector-ref v i))", 1);
    struct native_unit_result result = {0};
    driver->context.optimization = optimize;
    assert(native_compile_unit(&driver->context, &driver->object, &result));
    assert(hir_verify_scalar_tree(&driver->context, driver->hir.count, 0));
    assert(ssa_verify_function(&driver->context));
    assert(lir_verify_function(&driver->context));
    unsigned seen = 0;
    for (uintptr_t index = 0; index < driver->signature_context.signature_count;
         index++) {
        struct native_signature *signature = &driver->storage.signatures[index];
        if (signature->runtime_id < 24) continue;
        seen++;
        assert(native_runtime_signature_p(&driver->context, signature));
        uint32_t saved_result = signature->result_code;
        signature->result_code = 11;
        assert(!native_runtime_signature_p(&driver->context, signature));
        signature->result_code = saved_result;
        uint32_t saved_effect = signature->allocation_free;
        signature->allocation_free = !saved_effect;
        assert(!native_runtime_signature_p(&driver->context, signature));
        signature->allocation_free = saved_effect;
        struct native_parameter *parameter =
            &driver->storage.parameters[signature->first_parameter];
        uintptr_t saved_size = parameter->size;
        parameter->size = 1;
        assert(!native_runtime_signature_p(&driver->context, signature));
        parameter->size = saved_size;
        assert(native_runtime_signature_p(&driver->context, signature));
        if (signature->runtime_id == 26) {
            signature->result_code = 2;
            assert(!hir_verify_scalar_tree(&driver->context, driver->hir.count, 0));
            assert(!ssa_verify_function(&driver->context));
            assert(!lir_verify_function(&driver->context));
            signature->result_code = saved_result;
            assert(lir_verify_function(&driver->context));
        }
    }
    assert(seen == 5);
    release(driver);
}

int main(void) {
    /* Even a zero-byte unit can prepare the complete seed catalogue. */
    struct native_driver *empty = prepare("", 1);
    assert(empty->environment.symbol_count == 1054);
    assert(empty->environment.present_count == 1121);
    release(empty);
    for (unsigned optimize = 0; optimize < 2; optimize++) {
        check("(defun f (v) (declare (type value v) (returns usize))"
              " (without-allocation (value-vector-length v)))", 1, 0, 1920, optimize);
        check("(defun f () (declare (returns value)) (make-value-vector 0 nil))",
              1, 0, 1920, optimize);
        check("(defun f (v) (declare (type value v) (returns usize))"
              " (value-vector-push v nil))", 1, 0, 1920, optimize);
        check("(defun f (v) (declare (type value v) (returns value))"
              " (without-allocation (value-vector-set v 0 nil)))", 1, 0, 1920, optimize);
        check("(defun f () (declare (returns value))"
              " (without-allocation (make-value-vector 0 nil)))", 1, 9, 0, optimize);
        check("(defun f (v) (declare (type value v) (returns usize))"
              " (without-allocation (value-vector-push v nil)))", 1, 9, 0, optimize);
        check("(defun f () (declare (returns value)) (make-value-vector 0 nil))",
              0, 5, 0, optimize);
        check("(defun f (v) (declare (type value v) (returns value))"
              " (value-vector-ref v -1))", 1, 6, 0, optimize);
        check("(defun f (v) (declare (type u64 v) (returns usize))"
              " (value-vector-length v))", 1, 6, 0, optimize);
        check("(defun f () (declare (returns value)) (make-value-vector 1 (wrap-cast u64 0)))",
              1, 6, 0, optimize);
        check("(ffi:export-data \"psl_rt_value_vector_ref\" u64 0)",
              1, 11, 0, optimize);
        check("(defpackage :local-vectors (:use :cl)) (in-package :local-vectors)"
              " (defun value-vector-length (x)"
              " (declare (type psl:u64 x) (psl:returns psl:u64)) (psl:wrap+ x 1))"
              " (defun f (x) (declare (type psl:u64 x) (psl:returns psl:u64))"
              " (value-vector-length x))", 1, 0, 0, optimize);
        check("(defun f () (declare (returns value)) (make-value-vector 1))",
              1, 6, 0, optimize);
        check("(defun f (v) (declare (type value v) (returns value))"
              " (value-vector-set v 0))", 1, 6, 0, optimize);
        check_receivers(optimize);
    }
    puts("Native vector profiles, effects, module closure and IR receivers passed");
    return 0;
}
