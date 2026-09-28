#include "../bootstrap/host/source.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef PSL_TEST_ALLOCATOR_FAULTS
void *__real_calloc(size_t, size_t);
void *__real_realloc(void *, size_t);
void __real_free(void *);

static void *live_allocations[16];
static size_t allocation_calls, fail_at, live_count;

static void remember_allocation(void *memory) {
    assert(memory && live_count < sizeof live_allocations / sizeof *live_allocations);
    live_allocations[live_count++] = memory;
}

static size_t find_allocation(void *memory) {
    for (size_t index = 0; index < live_count; ++index) {
        if (live_allocations[index] == memory) return index;
    }
    assert(!"free or realloc of untracked memory");
    return 0;
}

static void forget_allocation(size_t index) {
    live_allocations[index] = live_allocations[--live_count];
}

void *__wrap_calloc(size_t count, size_t size) {
    if (++allocation_calls == fail_at) return NULL;
    void *memory = __real_calloc(count, size);
    if (memory) remember_allocation(memory);
    return memory;
}

void *__wrap_realloc(void *memory, size_t size) {
    size_t index = memory ? find_allocation(memory) : 0;
    if (++allocation_calls == fail_at) return NULL;
    void *resized = __real_realloc(memory, size);
    if (!resized) return NULL;
    if (memory) live_allocations[index] = resized;
    else remember_allocation(resized);
    return resized;
}

void __wrap_free(void *memory) {
    if (memory) forget_allocation(find_allocation(memory));
    __real_free(memory);
}
#endif

static uint8_t expected_byte(size_t index) {
    return (uint8_t)((index * 131u + index / 7u) & 0xffu);
}

static void write_fixture(const char *path, size_t size) {
    FILE *stream = fopen(path, "wb");
    assert(stream);
    for (size_t index = 0; index < size; ++index) {
        assert(fputc(expected_byte(index), stream) != EOF);
    }
    assert(fclose(stream) == 0);
}

static void check_fixture(const char *path, size_t expected_size) {
    size_t length = SIZE_MAX;
    uint8_t *bytes = native_source_read_file((const uint8_t *)path, &length);
    assert(bytes && length == expected_size && bytes[length] == 0);
    for (size_t index = 0; index < length; ++index) {
        assert(bytes[index] == expected_byte(index));
    }
    free(bytes);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(live_count == 0);
#endif
}

int main(int argc, char **argv) {
    char empty[1024], boundary[1024], large[1024], missing[1024];
    assert(argc == 2);
    assert(snprintf(empty, sizeof empty, "%s/empty", argv[1]) > 0);
    assert(snprintf(boundary, sizeof boundary, "%s/boundary", argv[1]) > 0);
    assert(snprintf(large, sizeof large, "%s/large", argv[1]) > 0);
    assert(snprintf(missing, sizeof missing, "%s/missing", argv[1]) > 0);
    write_fixture(empty, 0);
    write_fixture(boundary, 4095);
    write_fixture(large, 9000);
    check_fixture(empty, 0);
    check_fixture(boundary, 4095);
    check_fixture(large, 9000);
    size_t length = SIZE_MAX;
    assert(!native_source_read_file((const uint8_t *)missing, &length));
    assert(length == SIZE_MAX);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(live_count == 0);
    allocation_calls = fail_at = 0;
    check_fixture(large, 9000);
    size_t successful_calls = allocation_calls;
    for (size_t failure = 1; failure <= successful_calls; ++failure) {
        allocation_calls = 0;
        fail_at = failure;
        length = SIZE_MAX;
        assert(!native_source_read_file((const uint8_t *)large, &length));
        assert(length == SIZE_MAX && live_count == 0);
    }
#endif
    puts("PSL hosted source input and cleanup passed");
    return 0;
}
