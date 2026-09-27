#include "../bootstrap/native_api.h"
#include "../bootstrap/host/compiler.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum scenario { SUCCESS, READ_FAILURE, PREPARE_FAILURE, COMPILE_FAILURE, WRITE_FAILURE };
struct event { uint32_t kind; uintptr_t position, length; char text[64]; };
static enum scenario scenario;
static struct event events[2];
static size_t event_count, reads, prepares, compiles, writes, releases;
static uintptr_t phase;
static uint32_t expected_optimization = 1;
static uint32_t expected_target = NATIVE_TARGET_X86_64_LINUX;
static struct psl_ast_node nodes[3];
static struct native_signature signatures[2];
static struct native_function functions[2];
static uint8_t object_bytes[] = {0x7f, 'E', 'L', 'F'};

#ifdef PSL_TEST_ALLOCATOR_FAULTS
void *__real_calloc(size_t, size_t);
void __real_free(void *);
static void *state_allocation;
static int fail_state;

void *__wrap_calloc(size_t count, size_t size) {
    assert(count == 1 && size >= sizeof(struct native_driver) + sizeof(struct native_unit_result));
    assert(!state_allocation);
    if (fail_state) return NULL;
    state_allocation = __real_calloc(count, size);
    assert(state_allocation);
    return state_allocation;
}

void __wrap_free(void *memory) {
    if (memory == state_allocation) state_allocation = NULL;
    __real_free(memory);
}
#endif

uint8_t *native_read_source_unit(const char *path, size_t *length) {
    uint8_t *source;
    assert(strcmp(path, "source.lisp") == 0);
    ++reads;
    if (scenario == READ_FAILURE) return NULL;
    source = malloc(4);
    assert(source);
    memcpy(source, "raw", 4);
    *length = 3;
    return source;
}

int native_prepare_driver(struct native_driver *driver) {
    ++prepares;
    assert(driver->source && driver->length == 3);
    assert(!driver->context.source && !driver->parser.nodes);
    if (scenario == PREPARE_FAILURE) return 0;
    nodes[1].start = 33;
    nodes[0].start = 0;
    nodes[0].length = 3;
    nodes[2].start = 77;
    signatures[1].name = 3;
    functions[1].name = (const uint8_t *)"broken";
    functions[1].name_length = 6;
    driver->parser.nodes = nodes;
    driver->storage.signatures = signatures;
    driver->storage.functions = functions;
    driver->context.source = driver->source;
    driver->context.parser = &driver->parser;
    driver->object.data = object_bytes;
    driver->object.length = sizeof object_bytes;
    return 1;
}

int native_compile_unit(struct native_compile_context *context, struct byte_buffer *object,
                        struct native_unit_result *result) {
    ++compiles;
    assert(context->parser->nodes == nodes && context->source);
    assert(context->optimization == expected_optimization);
    assert(context->target == expected_target);
    assert(object->data == object_bytes && object->length == sizeof object_bytes);
    assert(!result->phase && !result->form && !result->index);
    if (scenario != COMPILE_FAILURE) return 1;
    result->phase = phase;
    result->form = 2;
    if (phase == 9) result->form = 1;
    result->index = 1;
    return 0;
}

int native_host_write_object(const uint8_t *path, const struct byte_buffer *object) {
    ++writes;
    assert(strcmp((const char *)path, "result.o") == 0);
    assert(object->data == object_bytes && object->length == sizeof object_bytes);
    return scenario != WRITE_FAILURE;
}

int native_release_driver(struct native_driver *driver) {
    ++releases;
    free(driver->source);
    driver->source = NULL;
    return 1;
}

void native_host_report_error(uint32_t kind, const uint8_t *text,
                              uintptr_t length, uintptr_t position) {
    struct event *event;
    assert(event_count < sizeof events / sizeof *events);
    event = &events[event_count++];
    event->kind = kind;
    event->position = position;
    event->length = length;
    if (text) {
        size_t size = length ? length : strlen((const char *)text);
        assert(size < sizeof event->text);
        memcpy(event->text, text, size);
        event->text[size] = 0;
    }
}

static void reset(enum scenario next) {
    scenario = next;
    event_count = reads = prepares = compiles = writes = releases = 0;
    memset(events, 0, sizeof events);
}

static void check_run(enum scenario next, int expected) {
    reset(next);
    assert(native_run_compiler("source.lisp", "result.o") == expected);
    assert(reads == 1 && releases == 1);
    assert(prepares == (size_t)(next != READ_FAILURE));
    assert(compiles == (size_t)(next != READ_FAILURE && next != PREPARE_FAILURE));
    assert(writes == (size_t)(next == SUCCESS || next == WRITE_FAILURE));
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(!state_allocation);
#endif
}

static void check_compilation_errors(void) {
    static const uint32_t kinds[] = {0, 6, 7, 8, 0, 9, 10, 0, 0, 11, 0};
    for (phase = 0; phase < sizeof kinds / sizeof *kinds; ++phase) {
        check_run(COMPILE_FAILURE, 1);
        assert(event_count == (size_t)(kinds[phase] ? 2 : 1));
        assert(events[event_count - 1].kind == NATIVE_HOST_UNSUPPORTED);
        assert(strcmp(events[event_count - 1].text, "source.lisp") == 0);
        if (!kinds[phase]) continue;
        assert(events[0].kind == kinds[phase]);
        if (phase <= 3) assert(events[0].position == 33);
        if (phase == 5) assert(events[0].position == 77);
        if (phase == 6) assert(events[0].length == 6 && strcmp(events[0].text, "broken") == 0);
        if (phase == 9) assert(events[0].length == 3 && strcmp(events[0].text, "raw") == 0);
    }
}

static void check_target_arguments(void) {
    const char *targets[] = {"--target=x86_64-linux-gnu", "--target=aarch64-linux-gnu"};
    for (uint32_t target = 0; target < 2; ++target) {
        expected_target = target;
        expected_optimization = 1;
        char *single[] = {"pslcc-native", (char *)targets[target], "source.lisp", "result.o", NULL};
        reset(SUCCESS);
        assert(native_compiler_main(4, single) == 0);
        assert(reads == 1 && writes == 1 && releases == 1 && !event_count);
        for (uint32_t level = 0; level < 2; ++level) {
            expected_optimization = level;
            char *flag = level ? "-O1" : "-O0";
            for (unsigned order = 0; order < 2; ++order) {
                char *args[] = {"pslcc-native", order ? flag : (char *)targets[target],
                    order ? (char *)targets[target] : flag, "source.lisp", "result.o", NULL};
                reset(SUCCESS);
                assert(native_compiler_main(5, args) == 0);
                assert(reads == 1 && writes == 1 && releases == 1 && !event_count);
            }
        }
    }
    const char *bad[] = {"--target=", "--target=aarch64-linux-gn", "--target=aarch64-linux-gnu-extra",
        "--target=x86_64-windows-gnu", "--target=riscv64-linux-gnu"};
    for (size_t i = 0; i < sizeof bad / sizeof *bad; ++i) {
        char *args[] = {"pslcc-native", (char *)bad[i], "source.lisp", "result.o", NULL};
        reset(SUCCESS);
        assert(native_compiler_main(4, args) == 2);
        assert(event_count == 1 && events[0].kind == NATIVE_HOST_USAGE && !reads && !releases);
    }
    char *duplicates[] = {"pslcc-native", "--target=aarch64-linux-gnu",
        "--target=x86_64-linux-gnu", "source.lisp", "result.o", NULL};
    reset(SUCCESS);
    assert(native_compiler_main(5, duplicates) == 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_USAGE && !reads && !releases);
    reset(SUCCESS);
    assert(native_run_compiler_target("source.lisp", "result.o", 1, 2) == 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_USAGE && !reads && !releases);
    expected_target = NATIVE_TARGET_X86_64_LINUX;
    expected_optimization = 1;
}

static void check_arguments(void) {
    int invalid[] = {-1, 0, 1, 2, 5};
    char *argv[] = {"pslcc-native", "source.lisp", "result.o", NULL};
    size_t i;
    for (i = 0; i < sizeof invalid / sizeof *invalid; ++i) {
        reset(SUCCESS);
        assert(native_compiler_main(invalid[i], NULL) == 2);
        assert(event_count == 1 && events[0].kind == NATIVE_HOST_USAGE);
        assert(!reads && !prepares && !compiles && !writes && !releases);
    }
    reset(SUCCESS);
    assert(native_compiler_main(3, argv) == 0);
    assert(reads == 1 && writes == 1 && releases == 1 && !event_count);
    for (uint32_t level = 0; level < 2; ++level) {
        char *options[] = {"pslcc-native", level ? "-O1" : "-O0", "source.lisp", "result.o", NULL};
        expected_optimization = level;
        reset(SUCCESS);
        assert(native_compiler_main(4, options) == 0);
        assert(reads == 1 && writes == 1 && releases == 1 && !event_count);
    }
    const char *bad[] = {"", "-", "-O", "-O2", "-O00", "-o0"};
    for (i = 0; i < sizeof bad / sizeof *bad; ++i) {
        char *options[] = {"pslcc-native", (char *)bad[i], "source.lisp", "result.o", NULL};
        reset(SUCCESS);
        assert(native_compiler_main(4, options) == 2);
        assert(event_count == 1 && events[0].kind == NATIVE_HOST_USAGE && !reads && !releases);
    }
    reset(SUCCESS);
    assert(native_run_compiler_options("source.lisp", "result.o", 2) == 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_USAGE && !reads && !releases);
    expected_optimization = 1;
}

int main(void) {
    check_run(SUCCESS, 0);
    assert(!event_count);
    check_run(READ_FAILURE, 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_READ);
    check_run(PREPARE_FAILURE, 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_ALLOCATE);
    check_run(WRITE_FAILURE, 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_WRITE);
    assert(strcmp(events[0].text, "result.o") == 0);
    check_compilation_errors();
    check_arguments();
    check_target_arguments();
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    reset(SUCCESS);
    fail_state = 1;
    assert(native_run_compiler("source.lisp", "result.o") == 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_ALLOCATE);
    assert(!reads && !prepares && !compiles && !writes && !releases && !state_allocation);
#endif
    puts("PSL compiler driver exit codes, diagnostics, and cleanup passed");
    return 0;
}
