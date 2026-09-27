#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char source[] =
    "(defun helper (value) (declare (type u64 value) (returns u64))"
    " (wrap+ value 7))"
    "(defun caller (value) (declare (type u64 value) (returns u64))"
    " (helper value))";

static void prepare_unit(struct native_driver *driver, uintptr_t cache_capacity) {
    struct native_unit_result result;
    memset(driver, 0, sizeof *driver);
    driver->source = malloc(sizeof source);
    assert(driver->source);
    memcpy(driver->source, source, sizeof source);
    driver->length = sizeof source - 1;
    assert(native_prepare_driver(driver));
    if (cache_capacity != UINTPTR_MAX)
        driver->context.inline_capacity = cache_capacity;
    if (!cache_capacity) driver->context.inline_values = NULL;
    assert(native_compile_unit(&driver->context, &driver->object, &result));
}

static void prepare(struct native_driver *driver) {
    prepare_unit(driver, UINTPTR_MAX);
    assert(driver->storage.signatures[0].inline_count);
    /* Keep the unit's verified templates, then rebuild the caller without
       optimization through the public single-function API. */
    driver->context.optimization = 0;
    assert(compile_scalar_form(&driver->context, driver->storage.signatures + 1,
                               driver->storage.functions + 1));
    assert(ssa_verify_function(&driver->context));
    driver->context.optimization = 1;
}

static size_t count_calls(const struct native_driver *driver) {
    size_t count = 0;
    for (size_t i = 0; i < driver->ssa.value_count; ++i)
        if (driver->ssa.values[i].kind == 7) ++count;
    return count;
}

static void expect_unchanged_rejection(struct native_driver *driver) {
    size_t count = driver->ssa.value_count;
    size_t bytes = count * sizeof *driver->ssa.values;
    void *before = malloc(bytes);
    assert(before);
    memcpy(before, driver->ssa.values, bytes);
    assert(!ssa_optimize_function(&driver->context));
    assert(driver->ssa.value_count == count);
    assert(memcmp(before, driver->ssa.values, bytes) == 0);
    free(before);
}

static void check_invalid_templates(void) {
    struct native_driver driver;
    prepare(&driver);
    struct native_signature *helper = driver.storage.signatures;
    uintptr_t base = helper->inline_base;
    helper->inline_base = UINTPTR_MAX;
    expect_unchanged_rejection(&driver);
    helper->inline_base = base;
    uintptr_t result = helper->inline_result;
    helper->inline_result = helper->inline_count + 1;
    expect_unchanged_rejection(&driver);
    helper->inline_result = result;
    struct native_ssa_value *parameter = driver.context.inline_values + base;
    assert(parameter->kind == 2);
    uint64_t position = parameter->value;
    parameter->value = 0;
    expect_unchanged_rejection(&driver);
    parameter->value = position;
    struct native_ssa_value *operation = parameter + helper->inline_count - 1;
    uintptr_t left = operation->left;
    operation->left = helper->inline_count + 1;
    expect_unchanged_rejection(&driver);
    operation->left = left;
    assert(ssa_optimize_function(&driver.context));
    assert(!count_calls(&driver) && ssa_verify_function(&driver.context));
    assert(native_release_driver(&driver));
}

static void check_capacity_fallback(void) {
    struct native_driver driver;
    prepare(&driver);
    driver.ssa.value_capacity = driver.ssa.value_count;
    assert(ssa_optimize_function(&driver.context));
    assert(count_calls(&driver) == 1 && ssa_verify_function(&driver.context));
    assert(native_release_driver(&driver));
}

static void check_cache_fallback(uintptr_t capacity) {
    struct native_driver driver;
    prepare_unit(&driver, capacity);
    assert(!driver.context.inline_count && !driver.storage.signatures[0].inline_count);
    assert(count_calls(&driver) == 1 && ssa_verify_function(&driver.context));
    assert(native_release_driver(&driver));
}

int main(void) {
    check_invalid_templates();
    check_capacity_fallback();
    check_cache_fallback(0);
    check_cache_fallback(1);
    puts("PSL inliner rejects invalid templates and preserves calls at capacity");
    return 0;
}
