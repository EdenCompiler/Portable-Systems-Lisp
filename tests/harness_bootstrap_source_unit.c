#include "../bootstrap/host/source.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* An in-memory OS adapter exercises traversal independently of filesystem I/O. */
struct fixture { const char *path, *text; };
static const struct fixture fixtures[] = {
    {"/unit/main.lisp", "(include \"shared.lisp\") (include \"alias.lisp\") "
        "(include \"sub/child.lisp\") (include \"empty.lisp\") "
        "(defun answer () (declare (returns u64)) 42)"},
    {"/unit/shared.lisp", "(defun helper () (declare (returns u64)) 1)"},
    {"/unit/sub/child.lisp", "(include \"../shared.lisp\") "
        "(defun child () (declare (returns u64)) 2)"},
    {"/unit/empty.lisp", "; no forms\n"},
    {"/unit/cycle.lisp", "(include \"cycle.lisp\")"},
    {"/unit/invalid.lisp", "(include unquoted)"},
    {"/unit/reader.lisp", "(include \"shared.lisp\""},
    {"/unit/missing.lisp", "(include \"absent.lisp\")"},
    {"/unit/unreadable.lisp", NULL},
    {"/unit/c-main.lisp", "(include \"sub/c-child.lisp\") "
        "(defun answer () (declare (returns u64)) 42)"},
    {"/unit/sub/c-child.lisp", "(ffi:source \"../native.c\") "
        "(defun child () (declare (returns u64)) 2)"},
    {"/unit/native.c", "int native_helper(void) { return 42; }"},
    {"/unit/c-duplicate.lisp", "(ffi:source \"native.c\") "
        "(ffi:source \"./native.c\")"},
    {"C:\\unit\\main.lisp", "(include \"sibling.lisp\") "
        "(include \"D:\\\\lib\\\\shared.lisp\") "
        "(include \"\\\\rooted.lisp\") (include \"/absolute.lisp\")"},
    {"C:\\unit\\sibling.lisp", "(sibling)"},
    {"D:\\lib\\shared.lisp", "(drive)"},
    {"\\rooted.lisp", "(rooted)"},
    {"/absolute.lisp", "(absolute)"}
};
static unsigned error_kind;
static int windows_paths;

#ifdef PSL_TEST_ALLOCATOR_FAULTS
void *__real_malloc(size_t);
void *__real_calloc(size_t, size_t);
void *__real_realloc(void *, size_t);
void __real_free(void *);
static void *live[512];
static size_t calls, fail_at, live_count;

static int fail_allocation(void) {
    return ++calls == fail_at;
}

static void *remember(void *memory) {
    size_t i;
    assert(memory);
    for (i = 0; i < sizeof live / sizeof *live; ++i) {
        if (live[i]) continue;
        live[i] = memory;
        ++live_count;
        return memory;
    }
    abort();
}

void *__wrap_malloc(size_t size) {
    return fail_allocation() ? NULL : remember(__real_malloc(size));
}

void *__wrap_calloc(size_t count, size_t size) {
    return fail_allocation() ? NULL : remember(__real_calloc(count, size));
}

void *__wrap_realloc(void *memory, size_t size) {
    size_t i;
    void *result;
    if (!memory) {
        return fail_allocation() ? NULL : remember(__real_realloc(NULL, size));
    }
    for (i = 0; i < sizeof live / sizeof *live; ++i) if (live[i] == memory) break;
    assert(i < sizeof live / sizeof *live);
    if (fail_allocation()) return NULL;
    result = __real_realloc(memory, size);
    assert(result);
    live[i] = result;
    return result;
}

void __wrap_free(void *memory) {
    size_t i;
    if (!memory) return;
    for (i = 0; i < sizeof live / sizeof *live; ++i) {
        if (live[i] != memory) continue;
        live[i] = NULL;
        --live_count;
        __real_free(memory);
        return;
    }
    abort();
}
#endif

static const struct fixture *find_fixture(const uint8_t *path) {
    size_t i;
    for (i = 0; i < sizeof fixtures / sizeof *fixtures; ++i)
        if (strcmp(fixtures[i].path, (const char *)path) == 0) return &fixtures[i];
    return NULL;
}

uint8_t *native_source_canonical_path(const uint8_t *path) {
    const struct fixture *fixture;
    uint8_t *copy;
    if (strcmp((const char *)path, "/unit/alias.lisp") == 0 ||
        strcmp((const char *)path, "/unit/sub/../shared.lisp") == 0)
        path = (const uint8_t *)"/unit/shared.lisp";
    if (strcmp((const char *)path, "/unit/./native.c") == 0)
        path = (const uint8_t *)"/unit/native.c";
    if (strcmp((const char *)path, "/unit/sub/../native.c") == 0)
        path = (const uint8_t *)"/unit/native.c";
    fixture = find_fixture(path);
    if (!fixture) return NULL;
    copy = malloc(strlen(fixture->path) + 1);
    if (copy) strcpy((char *)copy, fixture->path);
    return copy;
}

uint8_t *native_source_read_file(const uint8_t *path, size_t *length) {
    const struct fixture *fixture = find_fixture(path);
    uint8_t *bytes;
    if (!fixture || !fixture->text) return NULL;
    bytes = malloc(strlen(fixture->text) + 1);
    if (bytes) {
        strcpy((char *)bytes, fixture->text);
        *length = strlen(fixture->text);
    }
    return bytes;
}

int native_source_windows_paths(void) { return windows_paths; }

void native_source_report_error(uint32_t kind, const uint8_t *path) {
    assert(path && kind >= 1 && kind <= 5);
    error_kind = kind;
}

static void release_c_sources(struct native_c_source_path *source) {
    while (source) {
        struct native_c_source_path *next = source->next;
        free(source->path);
        free(source);
        source = next;
    }
}

static void check_success(const char *path, const char *expected) {
    size_t length = 999;
    uint8_t *bytes;
    error_kind = 0;
    struct native_c_source_path *c_sources = NULL;
    bytes = native_read_source_unit(path, &length, &c_sources);
    assert(!c_sources);
    assert(bytes && length == strlen(expected) && !error_kind);
    assert(memcmp(bytes, expected, length + 1) == 0);
    free(bytes);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(!live_count);
#endif
}

static void check_error(const char *path, unsigned expected) {
    size_t length = 999;
    error_kind = 0;
    struct native_c_source_path *c_sources = NULL;
    assert(!native_read_source_unit(path, &length, &c_sources));
    assert(!c_sources);
    assert(length == 999 && error_kind == expected);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(!live_count);
#endif
}

static void check_c_source(void) {
    const char expected[] =
        "(defun child () (declare (returns u64)) 2)\n"
        "(defun answer () (declare (returns u64)) 42)\n";
    struct native_c_source_path *c_sources = NULL;
    size_t length = 999;
    uint8_t *bytes;
    error_kind = 0;
    bytes = native_read_source_unit("/unit/c-main.lisp", &length, &c_sources);
    assert(bytes && !error_kind && length == strlen(expected));
    assert(memcmp(bytes, expected, length + 1) == 0);
    assert(c_sources && !c_sources->next);
    assert(strcmp((const char *)c_sources->path, "/unit/native.c") == 0);
    free(bytes);
    release_c_sources(c_sources);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(!live_count);
#endif
}

#ifdef PSL_TEST_ALLOCATOR_FAULTS
static void check_allocation_failures(const char *path) {
    size_t length, baseline, i;
    uint8_t *bytes;
    fail_at = calls = 0;
    struct native_c_source_path *c_sources = NULL;
    bytes = native_read_source_unit(path, &length, &c_sources);
    assert(!c_sources);
    assert(bytes);
    baseline = calls;
    free(bytes);
    assert(!live_count);
    for (i = 1; i <= baseline; ++i) {
        fail_at = i;
        calls = 0;
        struct native_c_source_path *c_sources = NULL;
        assert(!native_read_source_unit(path, &length, &c_sources));
        assert(!c_sources);
        assert(!live_count);
    }
    fail_at = 0;
}

static void check_c_source_allocation_failures(void) {
    size_t length, baseline, i;
    uint8_t *bytes;
    struct native_c_source_path *c_sources = NULL;
    fail_at = calls = 0;
    bytes = native_read_source_unit("/unit/c-main.lisp", &length, &c_sources);
    assert(bytes && c_sources);
    baseline = calls;
    free(bytes);
    release_c_sources(c_sources);
    assert(!live_count);
    for (i = 1; i <= baseline; ++i) {
        c_sources = NULL;
        fail_at = i;
        calls = 0;
        assert(!native_read_source_unit("/unit/c-main.lisp", &length,
                                        &c_sources));
        assert(!c_sources && !live_count);
    }
    fail_at = 0;
}
#endif

int main(void) {
    const char expected[] =
        "(defun helper () (declare (returns u64)) 1)\n"
        "(defun child () (declare (returns u64)) 2)\n"
        "(defun answer () (declare (returns u64)) 42)\n";
    check_success("/unit/main.lisp", expected);
    check_success("/unit/empty.lisp", "");
    check_error("/unit/cycle.lisp", 2);
    check_error("/unit/invalid.lisp", 3);
    check_error("/unit/reader.lisp", 4);
    check_error("/unit/missing.lisp", 1);
    check_error("/unit/unreadable.lisp", 1);
    check_error("/unit/c-duplicate.lisp", 5);
    check_c_source();
    check_success("/unit/main.lisp", expected);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    check_allocation_failures("/unit/main.lisp");
    check_allocation_failures("/unit/empty.lisp");
    check_c_source_allocation_failures();
#endif
    windows_paths = 1;
    check_success("C:\\unit\\main.lisp", "(sibling)\n(drive)\n(rooted)\n(absolute)\n");
    puts("PSL source traversal, path policy, and ownership passed");
    return 0;
}
