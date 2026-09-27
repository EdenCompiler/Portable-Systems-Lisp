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
    assert(path && kind >= 1 && kind <= 4);
    error_kind = kind;
}

static void check_success(const char *path, const char *expected) {
    size_t length = 999;
    uint8_t *bytes;
    error_kind = 0;
    bytes = native_read_source_unit(path, &length);
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
    assert(!native_read_source_unit(path, &length));
    assert(length == 999 && error_kind == expected);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(!live_count);
#endif
}

#ifdef PSL_TEST_ALLOCATOR_FAULTS
static void check_allocation_failures(const char *path) {
    size_t length, baseline, i;
    uint8_t *bytes;
    fail_at = calls = 0;
    bytes = native_read_source_unit(path, &length);
    assert(bytes);
    baseline = calls;
    free(bytes);
    assert(!live_count);
    for (i = 1; i <= baseline; ++i) {
        fail_at = i;
        calls = 0;
        assert(!native_read_source_unit(path, &length));
        assert(!live_count);
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
    check_success("/unit/main.lisp", expected);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    check_allocation_failures("/unit/main.lisp");
    check_allocation_failures("/unit/empty.lisp");
#endif
    windows_paths = 1;
    check_success("C:\\unit\\main.lisp", "(sibling)\n(drive)\n(rooted)\n(absolute)\n");
    puts("PSL source traversal, path policy, and ownership passed");
    return 0;
}
