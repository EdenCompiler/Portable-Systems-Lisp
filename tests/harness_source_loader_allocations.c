#include "../bootstrap/host/source.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>

void *__real_malloc(size_t);
void *__real_calloc(size_t, size_t);
void *__real_realloc(void *, size_t);
void __real_free(void *);
static void *owned[8192];
static size_t live, attempts, fail_at = SIZE_MAX;
static int inject;

static size_t find_owned(void *pointer) {
    for (size_t i = 0; i < live; ++i) if (owned[i] == pointer) return i;
    return live;
}
static void remember(void *pointer) {
    if (pointer) { assert(live < sizeof owned / sizeof *owned); owned[live++] = pointer; }
}
static int fail_allocation(void) { return inject && attempts++ == fail_at; }
void *__wrap_malloc(size_t size) {
    if (fail_allocation()) return NULL;
    void *pointer = __real_malloc(size); remember(pointer); return pointer;
}
void *__wrap_calloc(size_t count, size_t size) {
    if (fail_allocation()) return NULL;
    void *pointer = __real_calloc(count, size); remember(pointer); return pointer;
}
void *__wrap_realloc(void *pointer, size_t size) {
    if (fail_allocation()) return NULL;
    size_t index = find_owned(pointer);
    void *replacement = __real_realloc(pointer, size);
    if (replacement) {
        if (index < live) owned[index] = replacement; else remember(replacement);
    }
    return replacement;
}
void __wrap_free(void *pointer) {
    size_t index = find_owned(pointer);
    if (index < live) owned[index] = owned[--live];
    __real_free(pointer);
}
void native_source_report_error(uint32_t kind, const uint8_t *path) {
    (void)kind; (void)path;
}
static size_t descriptors(void) {
    DIR *directory = opendir("/proc/self/fd");
    assert(directory);
    size_t count = 0;
    while (readdir(directory)) ++count;
    assert(!closedir(directory));
    return count;
}
static int read_unit(const char *path) {
    size_t length = 0;
    struct native_c_source_path *sources = NULL;
    uint8_t *bytes = native_read_source_unit(path, &length, &sources);
    int ok = bytes != NULL;
    if (ok) assert(bytes[length] == 0 && length != 0);
    free(bytes);
    while (sources) {
        struct native_c_source_path *next = sources->next;
        free(sources->path); free(sources); sources = next;
    }
    return ok;
}
int main(int argc, char **argv) {
    assert(argc >= 2);
    size_t initial_fds = descriptors();
    for (int input = 1; input < argc; ++input) {
        inject = 1; attempts = 0; fail_at = SIZE_MAX;
        assert(read_unit(argv[input]));
        size_t baseline = attempts;
        assert(baseline && live == 0 && descriptors() == initial_fds);
        for (size_t failure = 0; failure < baseline; ++failure) {
            attempts = 0; fail_at = failure;
            assert(!read_unit(argv[input]));
            assert(live == 0 && descriptors() == initial_fds);
        }
        attempts = 0; fail_at = SIZE_MAX;
        assert(read_unit(argv[input]));
        assert(live == 0 && descriptors() == initial_fds);
        printf("source unit releases owned storage and files across %zu allocation failures\n", baseline);
    }
    return 0;
}
