#include "../bootstrap/native_api.h"
#include "../bootstrap/host/compiler.h"
#include "../bootstrap/host/source.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


enum scenario { SUCCESS, READ_FAILURE, PREPARE_FAILURE, COMPILE_FAILURE, WRITE_FAILURE, IR_WRITE_FAILURE, IR_CAPACITY_FAILURE, IR_REPREPARE_FAILURE };
struct event { uint32_t kind; uintptr_t position, length; char text[64]; };
static enum scenario scenario;
static struct event events[2];
static size_t event_count, reads, prepares, compiles, writes, releases;
static uintptr_t phase;
static uint32_t expected_dump_stages;
static size_t ir_writes;
static uint32_t expected_optimization = 1;
static uint32_t expected_target = NATIVE_TARGET_X86_64_LINUX;
static uint32_t expected_profile;
static struct psl_ast_node nodes[3];
static struct native_signature signatures[2];
static struct native_function functions[2];
static uint8_t object_bytes[] = {0x7f, 'E', 'L', 'F'};

#ifdef PSL_TEST_ALLOCATOR_FAULTS
void *__real_calloc(size_t, size_t);
void __real_free(void *);
static void *owned_allocations[8];
static size_t owned_count, allocation_count, fail_at;

void *__wrap_calloc(size_t count, size_t size) {
    ++allocation_count;
    if (fail_at && allocation_count == fail_at) return NULL;
    void *memory = __real_calloc(count, size);
    assert(memory && owned_count < sizeof owned_allocations / sizeof *owned_allocations);
    owned_allocations[owned_count++] = memory;
    return memory;
}

void __wrap_free(void *memory) {
    for (size_t i = 0; i < owned_count; ++i) {
        if (owned_allocations[i] == memory) {
            owned_allocations[i] = owned_allocations[--owned_count];
            break;
        }
    }
    __real_free(memory);
}
#endif

uint8_t *native_read_source_unit(const char *path, size_t *length,
                                 struct native_c_source_path **c_sources) {
    uint8_t *source;
    assert(strcmp(path, "source.lisp") == 0);
    assert(c_sources && !*c_sources);
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
    if (scenario == PREPARE_FAILURE ||
        (scenario == IR_REPREPARE_FAILURE && prepares > 1)) return 0;
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
    assert(context->profile == expected_profile);
    assert(object->data == object_bytes && object->length == sizeof object_bytes);
    assert(!result->phase && !result->form && !result->index);
    if (expected_dump_stages) {
        struct native_ir_dump *dump = context->ir_dump;
        assert(dump && dump->stages == expected_dump_stages && !dump->error);
        assert(dump->output && dump->output->data && !dump->output->length);
        assert(dump->output->capacity == (compiles == 1 ? 64 * 3 + 4096 : 2 * (64 * 3 + 4096)));
        if ((scenario == IR_CAPACITY_FAILURE || scenario == IR_REPREPARE_FAILURE) && compiles == 1) {
            dump->error = 2;
            dump->required = dump->output->capacity + 1;
            return 0;
        }
        memcpy(dump->output->data, "IR!\n", 4);
        dump->output->length = 4;
    } else {
        assert(!context->ir_dump);
    }
    if (scenario != COMPILE_FAILURE) return 1;
    result->phase = phase;
    result->form = 2;
    if (phase == 9) result->form = 1;
    result->index = 1;
    return 0;
}

int native_host_write_ir(const uint8_t *bytes, uintptr_t length) {
    ++ir_writes;
    assert(expected_dump_stages && bytes && length == 4);
    assert(memcmp(bytes, "IR!\n", 4) == 0);
    return scenario != IR_WRITE_FAILURE;
}

int native_host_write_object(const uint8_t *path, const struct byte_buffer *object) {
    ++writes;
    assert(strcmp((const char *)path, "result.o") == 0);
    assert(object->data == object_bytes && object->length == sizeof object_bytes);
    return scenario != WRITE_FAILURE;
}

int native_host_merge_c_sources(const uint8_t *path,
                                const struct byte_buffer *object,
                                const struct native_c_source_path *sources,
                                uint32_t target) {
    (void)path;
    (void)object;
    (void)sources;
    (void)target;
    assert(!"unexpected C-source merge in compiler controller fixture");
    return 0;
}

int native_release_driver(struct native_driver *driver) {
    ++releases;
    free(driver->source);
    driver->source = NULL;
    driver->context.source = NULL;
    driver->parser.nodes = NULL;
    return 1;
}

uint64_t native_host_runtime_roots(uint32_t target,
                                   const struct native_c_source_path *sources,
                                   const uint8_t *const *inputs,
                                   uintptr_t input_count) {
    (void)target;
    (void)sources;
    (void)inputs;
    (void)input_count;
    return 0;
}

int native_host_link_supported(void) {
    return 1;
}

int native_host_link_artifact(const uint8_t *path,
                              const struct byte_buffer *object,
                              const struct native_c_source_path *sources,
                              uint32_t target, uint32_t profile,
                              uint64_t runtime_modules, uint32_t kind,
                              const uint8_t *const *inputs,
                              uintptr_t input_count) {
    (void)profile;
    (void)runtime_modules;
    (void)kind;
    (void)inputs;
    (void)input_count;
    return sources ? native_host_merge_c_sources(path, object, sources, target)
                   : native_host_write_object(path, object);
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
        size_t size = length && kind != NATIVE_HOST_CLI_PARSE ? length : strlen((const char *)text);
        assert(size < sizeof event->text);
        memcpy(event->text, text, size);
        event->text[size] = 0;
    }
}

static void reset(enum scenario next) {
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    assert(!owned_count);
    allocation_count = fail_at = 0;
#endif
    scenario = next;
    expected_dump_stages = 0;
    ir_writes = 0;
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
    assert(!owned_count);
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
    const char *targets[] = {"--target=x86_64-linux-gnu", "--target=aarch64-linux-gnu",
                             "--target=riscv64-linux-gnu", "--target=x86_64-windows-gnu"};
    for (uint32_t target = 0; target < 4; ++target) {
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
        "--target=x86_64-windows-gn", "--target=riscv64-none-elf"};
    for (size_t i = 0; i < sizeof bad / sizeof *bad; ++i) {
        char *args[] = {"pslcc-native", (char *)bad[i], "source.lisp", "result.o", NULL};
        reset(SUCCESS);
        assert(native_compiler_main(4, args) == 1);
        assert(event_count == 1 && events[0].kind == NATIVE_HOST_CLI_PARSE && !reads && !releases);
    }
    char *duplicates[] = {"pslcc-native", "--target=aarch64-linux-gnu",
        "--target=x86_64-linux-gnu", "source.lisp", "result.o", NULL};
    expected_target = NATIVE_TARGET_X86_64_LINUX;
    reset(SUCCESS);
    assert(native_compiler_main(5, duplicates) == 0);
    assert(!event_count && reads == 1 && writes == 1 && releases == 1);
    reset(SUCCESS);
    assert(native_run_compiler_target("source.lisp", "result.o", 1, 4) == 2);
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
    for (int argc = -1; argc <= 0; ++argc) {
        reset(SUCCESS);
        assert(native_compiler_main(argc, argv) == 2);
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
        assert(native_compiler_main(4, options) == 1);
        assert(event_count == 1 && events[0].kind == NATIVE_HOST_CLI_PARSE && !reads && !releases);
    }
    reset(SUCCESS);
    assert(native_run_compiler_options("source.lisp", "result.o", 2) == 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_USAGE && !reads && !releases);
    expected_optimization = 1;
}

static void check_object_arguments(void) {
    const char *targets[] = {"x86_64-linux-gnu", "aarch64-linux-gnu",
                            "riscv64-linux-gnu", "x86_64-windows-gnu"};
    for (uint32_t target = 0; target < 4; target++) {
        for (uint32_t profile = 0; profile < 2; profile++) {
            for (uint32_t level = 0; level < 2; level++) {
                char *args[] = {"pslcc-native", "--target", (char *)targets[target],
                    "-c", "source.lisp", "--profile", profile ? "hosted" : "freestanding",
                    "-o", "result.o", level ? "-O1" : "-O0", NULL};
                expected_target = target;
                expected_profile = profile;
                expected_optimization = level;
                reset(SUCCESS);
                assert(native_compiler_main(10, args) == 0);
                assert(reads == 1 && writes == 1 && releases == 1 && !event_count);
                struct {
                    uint64_t before;
                    struct native_cli_options options;
                    uint64_t after;
                } parsed = {.before = UINT64_C(0x12345678abcdef01),
                            .after = UINT64_C(0xabcdef0123456789)};
                reset(SUCCESS);
                assert(native_parse_cli_options(10, (const char *const *)args,
                                                &parsed.options));
                assert(!reads && !prepares && !compiles && !writes && !releases);
                assert(parsed.before == UINT64_C(0x12345678abcdef01));
                assert(parsed.after == UINT64_C(0xabcdef0123456789));
                assert(parsed.options.optimization == level);
                assert(parsed.options.target == target && parsed.options.profile == profile);
                assert(!strcmp((const char *)parsed.options.source, "source.lisp"));
                assert(!strcmp((const char *)parsed.options.output, "result.o"));
            }
        }
    }
    expected_optimization = 1;
    expected_target = NATIVE_TARGET_X86_64_LINUX;
    expected_profile = 0;
    char *last_wins[] = {"pslcc-native", "-O0", "--profile=hosted", "-c",
        "-o", "unused.o", "source.lisp", "-O1", "--profile", "freestanding",
        "-o", "result.o", NULL};
    reset(SUCCESS);
    assert(native_compiler_main(12, last_wins) == 0);
    assert(reads == 1 && writes == 1 && releases == 1 && !event_count);

    char *bad[][8] = {
        {"pslcc-native", "-c", "source.lisp", NULL},
        {"pslcc-native", "-c", "source.lisp", "-o", NULL},
        {"pslcc-native", "-c", "-o", "result.o", NULL},
        {"pslcc-native", "-c", "source.lisp", "result.o", NULL},
        {"pslcc-native", "-c", "source.lisp", "-o", "result.o", "extra", NULL},
        {"pslcc-native", "--target", "riscv64-none-elf", "source.lisp", "result.o", NULL},
        {"pslcc-native", "--profile", "unknown", "source.lisp", "result.o", NULL},
        {"pslcc-native", "--emit=bad", "source.lisp", "-o", "result", NULL},
        {"pslcc-native", "-c", "--emit=exe", "source.lisp", "-o", "result", NULL},
        {"pslcc-native", "--link-input", NULL}
    };
    for (size_t index = 0; index < sizeof bad / sizeof *bad; index++) {
        int argc = 0;
        while (bad[index][argc]) argc++;
        reset(SUCCESS);
        int result;
        result = native_compiler_main(argc, bad[index]);
        assert(result == 1);
        assert(event_count == 1 && events[0].kind == NATIVE_HOST_CLI_PARSE);
        assert(!reads && !prepares && !compiles && !writes && !releases);
    }
}

static void check_link_cli_parse(void) {
    char *args[] = {"pslcc-native", "source.lisp", "-o", "app",
                    "--emit=shared", "--link-input=one.o",
                    "--link-input", "two.o", NULL};
    char *one_input_args[] = {"pslcc-native", "source.lisp", "-o", "app",
                              "--emit=shared", "--link-input=one.o", NULL};
    struct {
        const uint8_t *slot;
        uint64_t canary;
    } bounded = {NULL, UINT64_C(0xa1b2c3d4e5f60718)};
    const uint8_t *inputs[8] = {0};
    struct {
        uint64_t before;
        struct native_cli_options options;
        uint64_t after;
    } parsed = {.before = UINT64_C(0x1111222233334444),
                .after = UINT64_C(0x5555666677778888)};
    assert(native_parse_cli_options_with_inputs(
        8, (const char *const *)args, &parsed.options, inputs, 8));
    assert(parsed.before == UINT64_C(0x1111222233334444));
    assert(parsed.after == UINT64_C(0x5555666677778888));
    assert(parsed.options.kind == 2 && parsed.options.emit_specified == 1);
    assert(parsed.options.output_option == 1 && parsed.options.paths == 1);
    assert(parsed.options.link_input_count == 2);
    assert(!strcmp((const char *)parsed.options.link_inputs[0], "one.o"));
    assert(!strcmp((const char *)parsed.options.link_inputs[1], "two.o"));
    assert(native_parse_cli_options_with_inputs(
        6, (const char *const *)one_input_args, &parsed.options,
        &bounded.slot, 1));
    assert(!strcmp((const char *)bounded.slot, "one.o"));
    assert(bounded.canary == UINT64_C(0xa1b2c3d4e5f60718));
    assert(!native_parse_cli_options_with_inputs(
        8, (const char *const *)args, &parsed.options, &bounded.slot, 1));
    assert(bounded.canary == UINT64_C(0xa1b2c3d4e5f60718));
    assert(!native_parse_cli_options_with_inputs(
        8, (const char *const *)args, &parsed.options, NULL, 1));
    assert(!native_parse_cli_options(8, (const char *const *)args,
                                     &parsed.options));
}

static void check_cli_diagnostics(void) {
    char *help[] = {"pslcc-native", "--help", NULL};
    char *bare[] = {"pslcc-native", NULL};
    reset(SUCCESS);
    assert(native_compiler_main(2, help) == 0);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_CLI_HELP);
    assert(!reads && !prepares && !compiles && !writes && !releases);
    reset(SUCCESS);
    assert(native_compiler_main(1, bare) == 1);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_CLI_PARSE);
    assert(events[0].length == 4);
    assert(!reads && !prepares && !compiles && !writes && !releases);
}

static void check_ir_arguments(void) {
    const char *names[] = {"hir", "ssa", "lir", "all"};
    const uint32_t stages[] = {1, 2, 4, 7};
    expected_target = NATIVE_TARGET_X86_64_LINUX;
    expected_optimization = 1;
    expected_profile = 0;
    for (size_t i = 0; i < 4; ++i) {
        char option[32];
        snprintf(option, sizeof option, "--dump-ir=%s", names[i]);
        char *args[] = {"pslcc-native", "source.lisp", "result.o", option, NULL};
        reset(SUCCESS);
        expected_dump_stages = stages[i];
        assert(native_compiler_main(4, args) == 0);
        assert(reads == 1 && prepares == 1 && compiles == 1 && writes == 1);
        assert(releases == 1 && ir_writes == 1 && !event_count);
    }
    char *args[] = {"pslcc-native", "source.lisp", "result.o", "--dump-ir=all", NULL};
    reset(IR_WRITE_FAILURE);
    expected_dump_stages = 7;
    assert(native_compiler_main(4, args) == 1);
    assert(writes == 1 && ir_writes == 1 && releases == 1);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_IR_WRITE);
    reset(IR_CAPACITY_FAILURE);
    expected_dump_stages = 7;
    assert(native_compiler_main(4, args) == 0);
    assert(reads == 1 && prepares == 2 && compiles == 2);
    assert(writes == 1 && ir_writes == 1 && releases == 2 && !event_count);
    reset(IR_REPREPARE_FAILURE);
    expected_dump_stages = 7;
    assert(native_compiler_main(4, args) == 2);
    assert(reads == 1 && prepares == 2 && compiles == 1 && releases == 2);
    assert(!writes && !ir_writes && event_count == 1);
    assert(events[0].kind == NATIVE_HOST_ALLOCATE);
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    reset(SUCCESS);
    expected_dump_stages = 7;
    assert(native_compiler_main(4, args) == 0);
    size_t allocations = allocation_count;
    assert(allocations >= 3 && !owned_count);
    for (size_t i = 1; i <= allocations; ++i) {
        reset(SUCCESS);
        expected_dump_stages = 7;
        fail_at = i;
        assert(native_compiler_main(4, args) == 2);
        assert(!compiles && !writes && !ir_writes && !owned_count);
        assert(event_count == 1);
        if (i < allocations) {
            assert(events[0].kind == NATIVE_HOST_ALLOCATE);
            assert(!reads && !prepares && !releases);
        } else {
            assert(events[0].kind == NATIVE_HOST_IR_ALLOCATE);
            assert(reads == 1 && prepares == 1 && releases == 1);
        }
    }
    reset(IR_CAPACITY_FAILURE);
    expected_dump_stages = 7;
    fail_at = 4;
    assert(native_compiler_main(4, args) == 2);
    assert(reads == 1 && prepares == 1 && compiles == 1 && releases == 1);
    assert(!writes && !ir_writes && !owned_count && event_count == 1);
    assert(events[0].kind == NATIVE_HOST_IR_ALLOCATE);
#endif
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
    check_object_arguments();
    check_link_cli_parse();
    check_cli_diagnostics();
    check_ir_arguments();
#ifdef PSL_TEST_ALLOCATOR_FAULTS
    char *args[] = {"pslcc-native", "source.lisp", "result.o", NULL};
    reset(SUCCESS);
    assert(native_compiler_main(3, args) == 0);
    size_t cli_allocations = allocation_count;
    assert(cli_allocations && !owned_count);
    for(size_t index = 1; index <= cli_allocations; ++index) {
        reset(SUCCESS);
        fail_at = index;
        assert(native_compiler_main(3, args) == 2);
        assert(event_count == 1 && events[0].kind == NATIVE_HOST_ALLOCATE);
        assert(!reads && !prepares && !compiles && !writes && !releases && !owned_count);
    }
    reset(SUCCESS);
    fail_at = 1;
    assert(native_run_compiler("source.lisp", "result.o") == 2);
    assert(event_count == 1 && events[0].kind == NATIVE_HOST_ALLOCATE);
    assert(!reads && !prepares && !compiles && !writes && !releases && !owned_count);
#endif
    puts("PSL compiler driver exit codes, diagnostics, and cleanup passed");
    return 0;
}
