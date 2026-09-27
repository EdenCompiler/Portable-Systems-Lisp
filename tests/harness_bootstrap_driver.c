#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef PSL_TEST_ALLOCATOR_FAULTS
/* Observe production allocations through the linker; the compiler does not
   contain test allocators or depend on this harness. */
void *__real_calloc(size_t, size_t);
void __real_free(void *);
static void *allocations[18], *owned_source;
static size_t allocation_count, fail_at, live_count, source_frees;
static size_t capacity;
static const size_t item_sizes[] = {
    sizeof(struct psl_ast_node), sizeof(struct native_layout),
    sizeof(struct native_layout_field), sizeof(struct native_parameter),
    sizeof(struct native_function), sizeof(struct native_signature),
    sizeof(struct native_hir_node), sizeof(struct native_ssa_value),
    sizeof(struct native_ssa_block), sizeof(struct native_ir_type),
    sizeof(uintptr_t), sizeof(struct native_lir_instruction),
    sizeof(struct native_lir_block), sizeof(struct native_call_fixup),
    sizeof(struct native_call_fixup), sizeof(uintptr_t), 1, 1
};

void *__wrap_calloc(size_t count, size_t size) {
    size_t index = allocation_count++;
    size_t expected = capacity;
    assert(index < 18);
    if (index == 11) expected *= 6;
    if (index == 12 || index == 14 || index == 15) expected *= 3;
    if (index == 16) expected = 1048576;
    if (index == 17) expected = 1200000;
    assert(count == expected && size == item_sizes[index]);
    if (allocation_count == fail_at) return NULL;
    allocations[index] = __real_calloc(count, size);
    assert(allocations[index]);
    ++live_count;
    return allocations[index];
}

void __wrap_free(void *memory) {
    size_t i;
    if (!memory) return;
    if (memory == owned_source) {
        ++source_frees;
        owned_source = NULL;
    } else {
        for (i = 0; i < 18; ++i) {
            if (allocations[i] != memory) continue;
            allocations[i] = NULL;
            --live_count;
            break;
        }
        assert(i < 18);
    }
    __real_free(memory);
}
#endif

static void set_source(struct native_driver *driver) {
    const char source[] =
        "(defun answer () (declare (returns u64) (c-export :c)) 42)";
    driver->length = strlen(source);
    driver->source = malloc(driver->length + 1);
    assert(driver->source);
    memcpy(driver->source, source, driver->length + 1);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    owned_source = driver->source;
    capacity = driver->length + 1;
    allocation_count = live_count = source_frees = 0;
    memset(allocations, 0, sizeof allocations);
#endif
}

static void check_initialized(struct native_driver *d) {
    size_t cap = d->length + 1;
    assert(d->scanner.data == d->source && d->scanner.length == d->length);
    assert(d->scanner.cursor == 0 && d->scanner.error == 0);
    assert(d->parser.scanner == &d->scanner && d->parser.token == &d->token);
    assert(!d->parser.has_token && !d->parser.count && !d->parser.error);
    assert(d->parser.nodes == d->storage.syntax && d->parser.capacity == cap);
    assert(d->layouts.parser == &d->parser && d->layouts.source == d->source);
    assert(d->layouts.layouts == d->storage.layouts && !d->layouts.layout_count);
    assert(d->layouts.fields == d->storage.fields && !d->layouts.field_count);
    assert(d->layouts.layout_capacity == cap && d->layouts.field_capacity == cap);
    assert(d->layouts.scratch == &d->shape && !d->layouts.error);
    assert(d->signature_context.layouts == &d->layouts);
    assert(d->signature_context.signatures == d->storage.signatures);
    assert(d->signature_context.parameters == d->storage.parameters);
    assert(d->signature_context.signature_capacity == cap);
    assert(d->signature_context.parameter_capacity == cap);
    assert(!d->signature_context.signature_count && !d->signature_context.parameter_count);
    assert(!d->signature_context.error);
    assert(d->hir.nodes == d->storage.hir && d->hir.capacity == cap);
    assert(!d->hir.count && !d->hir.error);
    assert(d->ssa.values == d->storage.ssa && d->ssa.types == d->storage.types);
    assert(d->ssa.blocks == d->storage.ssa_blocks && d->ssa.block_capacity == cap);
    assert(d->ssa.value_capacity == cap && !d->ssa.value_count);
    assert(!d->ssa.block_count && !d->ssa.current && !d->ssa.error);
    assert(d->lir.instructions == d->storage.lir && d->lir.capacity == 6 * cap);
    assert(d->lir.types == d->storage.types && d->lir.value_capacity == cap);
    assert(d->lir.blocks == d->storage.lir_blocks && d->lir.label_capacity == 3 * cap);
    assert(!d->lir.count && !d->lir.value_count && !d->lir.label_count && !d->lir.error);
    assert(d->calls.items == d->storage.calls && d->calls.capacity == cap);
    assert(d->jumps.items == d->storage.jumps && d->jumps.capacity == 3 * cap);
    assert(!d->calls.count && !d->calls.error && !d->jumps.count && !d->jumps.error);
    assert(d->code.data == d->storage.code && d->code.capacity == 1048576);
    assert(d->object.data == d->storage.object && d->object.capacity == 1200000);
    assert(!d->code.length && !d->object.length);
    assert(d->context.parser == &d->parser && d->context.source == d->source);
    assert(d->context.integer == &d->integer && d->context.hir == &d->hir);
    assert(d->context.code == &d->code && d->context.fixups == &d->calls);
    assert(d->context.functions == d->storage.functions);
    assert(d->context.signatures == &d->signature_context);
    assert(d->context.ssa == &d->ssa && d->context.lir == &d->lir);
    assert(d->context.bindings == d->storage.bindings);
    assert(d->context.labels == d->storage.labels && d->context.jumps == &d->jumps);
    assert(!d->context.prior_count && !d->context.current_arity);
    assert(!d->context.current_signature && !d->context.expected_type);
    assert(!d->context.active_binding && !d->context.local_count);
    assert(!d->context.expected_pointee);
    assert(d->context.optimization == 1 && !d->context.fold_cursor && !d->context.fold_changed);
}

static void check_released(struct native_driver *driver) {
    const struct native_storage empty = {0};
    assert(native_release_driver(driver));
    assert(native_release_driver(driver));
    assert(!driver->source && !driver->length);
    assert(memcmp(&driver->storage, &empty, sizeof empty) == 0);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(!live_count && source_frees == 1);
#endif
}

static void test_prepare_compile_release(void) {
    struct native_driver driver = {0};
    struct native_unit_result result;
    size_t generation;
    for (generation = 0; generation < 2; ++generation) {
        set_source(&driver);
        assert(native_prepare_driver(&driver));
        check_initialized(&driver);
        assert(native_compile_unit(&driver.context, &driver.object, &result));
        assert(!result.phase && driver.object.length > 64);
        assert(memcmp(driver.object.data, "\177ELF", 4) == 0);
        check_released(&driver);
    }
}

static void test_invalid_capacity(void) {
    struct native_driver driver = {0};
    const size_t lengths[] = {SIZE_MAX, SIZE_MAX / 6, SIZE_MAX / 2};
    size_t i;
    assert(!native_prepare_driver(&driver));
    assert(native_release_driver(&driver));
    for (i = 0; i < sizeof lengths / sizeof lengths[0]; ++i) {
        set_source(&driver);
        driver.length = lengths[i];
        assert(!native_prepare_driver(&driver));
#ifdef PSL_TEST_ALLOCATOR_FAULTS
        assert(!allocation_count);
#endif
        check_released(&driver);
    }
}

#ifdef PSL_TEST_ALLOCATOR_FAULTS
static void test_partial_allocations(void) {
    struct native_driver driver = {0};
    for (fail_at = 1; fail_at <= 18; ++fail_at) {
        set_source(&driver);
        assert(!native_prepare_driver(&driver));
        check_released(&driver);
    }
    fail_at = 0;
}
#endif

int main(void) {
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    test_partial_allocations();
#endif
    test_invalid_capacity();
    test_prepare_compile_release();
    puts("PSL driver allocation, initialization, and cleanup passed");
    return 0;
}
