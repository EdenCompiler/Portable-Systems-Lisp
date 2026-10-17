#define _POSIX_C_SOURCE 200809L
#include "../native_api.h"
#include "compiler.h"
#include "source.h"
#include <stdint.h>

#if defined(__unix__) || defined(__APPLE__)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *target_compiler(uint32_t target) {
    switch (target) {
    case NATIVE_TARGET_X86_64_LINUX: return "gcc";
    case NATIVE_TARGET_AARCH64_LINUX: return "aarch64-linux-gnu-gcc";
    case NATIVE_TARGET_RISCV64_LINUX: return "riscv64-linux-gnu-gcc";
    case NATIVE_TARGET_X86_64_WINDOWS: return "x86_64-w64-mingw32-gcc";
    default: return NULL;
    }
}

static const char *target_linker(uint32_t target) {
    switch (target) {
    case NATIVE_TARGET_X86_64_NONE: return "ld";
    case NATIVE_TARGET_RISCV64_NONE: return "riscv64-unknown-elf-ld";
    default: return NULL;
    }
}

int native_host_link_supported(void) {
    return 1;
}

static const char *target_archiver(uint32_t target) {
    switch (target) {
    case NATIVE_TARGET_X86_64_LINUX: return "ar";
    case NATIVE_TARGET_AARCH64_LINUX: return "aarch64-linux-gnu-ar";
    case NATIVE_TARGET_RISCV64_LINUX: return "riscv64-linux-gnu-ar";
    case NATIVE_TARGET_X86_64_WINDOWS: return "x86_64-w64-mingw32-ar";
    default: return NULL;
    }
}

static const char *target_nm(uint32_t target) {
    switch (target) {
    case NATIVE_TARGET_X86_64_LINUX: return "nm";
    case NATIVE_TARGET_AARCH64_LINUX: return "aarch64-linux-gnu-nm";
    case NATIVE_TARGET_RISCV64_LINUX: return "riscv64-linux-gnu-nm";
    case NATIVE_TARGET_X86_64_WINDOWS: return "x86_64-w64-mingw32-nm";
    default: return NULL;
    }
}

static int run_tool(char *const arguments[]) {
    pid_t child = fork();
    int status;
    if (child < 0) return 0;
    if (child == 0) {
        execvp(arguments[0], arguments);
        _exit(127);
    }
    if (waitpid(child, &status, 0) != child) return 0;
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int write_object(const char *path, const struct byte_buffer *object) {
    FILE *stream = fopen(path, "wb");
    size_t written;
    int closed;
    if (!stream) return 0;
    written = fwrite(object->data, 1, object->length, stream);
    closed = fclose(stream);
    return written == object->length && closed == 0;
}

static size_t source_count(const struct native_c_source_path *source) {
    size_t count = 0;
    while (source) {
        ++count;
        source = source->next;
    }
    return count;
}

/* Publish by rename from the destination filesystem. A /tmp staging directory
   can be on a different device from the requested output. */
static char *output_temporary_directory(const char *output) {
    static const char suffix[] = ".psl-native-XXXXXX";
    const char *slash;
    size_t prefix;
    char *directory;
    if (!output) return NULL;
    slash = strrchr(output, '/');
    prefix = slash ? (size_t)(slash - output) + 1 : 0;
    if (prefix > SIZE_MAX - sizeof suffix) return NULL;
    directory = malloc(prefix + sizeof suffix);
    if (!directory) return NULL;
    memcpy(directory, output, prefix);
    memcpy(directory + prefix, suffix, sizeof suffix);
    if (!mkdtemp(directory)) {
        free(directory);
        return NULL;
    }
    return directory;
}

static const char *output_file_name(const char *output) {
    const char *name = output;
    const char *slash;
    if (!output || !*output) return NULL;
    slash = strrchr(output, '/');
    if (slash) name = slash + 1;
    if (!*name || strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
        return NULL;
    return name;
}

static void remove_temporary_files(char **objects, size_t count,
                                   const char *psl, const char *merged,
                                   const char *directory) {
    size_t index;
    for (index = 0; objects && index < count; ++index) {
        if (objects[index]) unlink(objects[index]);
        free(objects[index]);
    }
    if (psl) unlink(psl);
    if (merged) unlink(merged);
    rmdir(directory);
}

static int format_path(char *path, size_t capacity, const char *directory,
                       const char *name) {
    int length = snprintf(path, capacity, "%s/%s", directory, name);
    return length >= 0 && (size_t)length < capacity;
}

static int compile_sources(const char *compiler,
                           const struct native_c_source_path *source,
                           const char *directory, char **objects,
                           size_t count, uint32_t target) {
    size_t index;
    for (index = 0; index < count; ++index, source = source->next) {
        size_t length = strlen(directory) + 32;
        int written;
        char *arguments[9];
        size_t argument_count = 0;
        objects[index] = malloc(length);
        if (!objects[index]) return 0;
        written = snprintf(objects[index], length, "%s/c%zu.o", directory,
                           index);
        if (written < 0 || (size_t)written >= length)
            return 0;
        arguments[argument_count++] = (char *)compiler;
        arguments[argument_count++] = "-std=c11";
        arguments[argument_count++] = "-fno-stack-protector";
        if (target != NATIVE_TARGET_X86_64_WINDOWS)
            arguments[argument_count++] = "-fPIC";
        arguments[argument_count++] = "-c";
        arguments[argument_count++] = (char *)source->path;
        arguments[argument_count++] = "-o";
        arguments[argument_count++] = objects[index];
        arguments[argument_count] = NULL;
        if (!run_tool(arguments)) return 0;
    }
    return 1;
}

static int merge_objects(const char *compiler, const char *output,
                         const char *psl, char **objects, size_t count) {
    char **arguments = calloc(count + 6, sizeof *arguments);
    size_t index;
    int ok;
    if (!arguments) return 0;
    arguments[0] = (char *)compiler;
    arguments[1] = "-r";
    arguments[2] = "-o";
    arguments[3] = (char *)output;
    arguments[4] = (char *)psl;
    for (index = 0; index < count; ++index) arguments[index + 5] = objects[index];
    ok = run_tool(arguments);
    free(arguments);
    return ok;
}

static uint64_t runtime_symbol_module(const char *symbol) {
    static const struct { const char *prefix; uint64_t module; } entries[] = {
        {"psl_rt_fixnum", 1}, {"psl_rt_unbox_fixnum", 1},
        {"psl_rt_fixnum_p", 1}, {"psl_rt_nil_p", 1},
        {"psl_rt_truthy", 1}, {"psl_rt_eq", 1},
        {"psl_rt_cons", 2}, {"psl_rt_cons_precise", 2},
        {"psl_rt_car", 2}, {"psl_rt_cdr", 2},
        {"psl_rt_make_string", 4}, {"psl_rt_make_string_precise", 4},
        {"psl_rt_make_string_from_bytes", 4},
        {"psl_rt_make_string_from_bytes_precise", 4},
        {"psl_rt_string_length", 4},
        {"psl_rt_string_byte", 4}, {"psl_rt_string_set_byte", 4},
        {"psl_rt_make_symbol", 8}, {"psl_rt_make_symbol_precise", 8},
        {"psl_rt_symbol_name", 8},
        {"psl_rt_make_package", 16}, {"psl_rt_make_package_precise", 16},
        {"psl_rt_package_name", 16},
        {"psl_rt_intern", 16}, {"psl_rt_intern_precise", 16},
        {"psl_rt_make_closure", 32}, {"psl_rt_make_closure_precise", 32},
        {"psl_rt_call_closure", 32}, {"psl_rt_values2", 64},
        {"psl_rt_nth_value", 64}, {"psl_rt_value_count", 64},
        {"psl_rt_collect", 128}, {"psl_rt_collect_precise", 128},
        {"psl_rt_live_objects", 128}, {"psl_rt_live_value_handles", 128},
        {"psl_rt_value_handle_open", 128}, {"psl_rt_value_handle_get", 128},
        {"psl_rt_value_handle_set", 128}, {"psl_rt_value_handle_close", 128},
        {"psl_rt_push_roots", 128}, {"psl_rt_pop_roots", 128},
        {"psl_rt_kind", 128},
        {"psl_rt_make_value_vector_precise", 1024},
        {"psl_rt_value_vector_length", 1024}, {"psl_rt_value_vector_ref", 1024},
        {"psl_rt_value_vector_set", 1024}, {"psl_rt_value_vector_push_precise", 1024}
    };
    size_t index;
    for (index = 0; index < sizeof entries / sizeof *entries; ++index) {
        size_t length = strlen(entries[index].prefix);
        if (strlen(symbol) == length &&
            strcmp(symbol, entries[index].prefix) == 0)
            return entries[index].module;
    }
    return 0;
}

static uint64_t input_runtime_roots(uint32_t target,
                                    const uint8_t *const *inputs,
                                    uintptr_t input_count) {
    const char *nm = target_nm(target);
    uint64_t roots = 0;
    uintptr_t index;
    if (!nm) return UINT64_MAX;
    for (index = 0; index < input_count; ++index) {
        int descriptors[2];
        pid_t child;
        int status;
        FILE *stream;
        char line[4096];
        char *arguments[4];
        if (!inputs[index] || pipe(descriptors) != 0) return UINT64_MAX;
        child = fork();
        if (child < 0) {
            close(descriptors[0]); close(descriptors[1]);
            return UINT64_MAX;
        }
        if (child == 0) {
            dup2(descriptors[1], STDOUT_FILENO);
            close(descriptors[0]); close(descriptors[1]);
            arguments[0] = (char *)nm;
            arguments[1] = "-u";
            arguments[2] = (char *)inputs[index];
            arguments[3] = NULL;
            execvp(arguments[0], arguments);
            _exit(127);
        }
        close(descriptors[1]);
        stream = fdopen(descriptors[0], "r");
        if (!stream) {
            close(descriptors[0]);
            waitpid(child, &status, 0);
            return UINT64_MAX;
        }
        while (fgets(line, sizeof line, stream)) {
            char *symbol = line + strlen(line);
            while (symbol > line &&
                   (symbol[-1] == '\n' || symbol[-1] == '\r' ||
                    symbol[-1] == ' ' || symbol[-1] == '\t')) --symbol;
            *symbol = '\0';
            while (symbol > line && symbol[-1] != ' ' && symbol[-1] != '\t')
                --symbol;
            if (strncmp(symbol, "psl_rt_", 7) == 0) {
                uint64_t module = runtime_symbol_module(symbol);
                if (!module) {
                    fclose(stream);
                    waitpid(child, &status, 0);
                    return UINT64_MAX;
                }
                roots |= module;
            }
        }
        fclose(stream);
        if (waitpid(child, &status, 0) != child || !WIFEXITED(status) ||
            WEXITSTATUS(status) != 0)
            return UINT64_MAX;
    }
    return roots;
}

static uint64_t source_runtime_roots(uint32_t target,
                                     const struct native_c_source_path *sources) {
    const char *compiler = target_compiler(target);
    size_t count = source_count(sources), index;
    char directory[] = "/tmp/psl-native-roots-XXXXXX";
    char **objects = NULL;
    const uint8_t **paths = NULL;
    uint64_t roots = UINT64_MAX;
    if (!count) return 0;
    if (!compiler || !mkdtemp(directory)) return UINT64_MAX;
    objects = calloc(count, sizeof *objects);
    paths = calloc(count, sizeof *paths);
    if (!objects || !paths ||
        !compile_sources(compiler, sources, directory, objects, count, target))
        goto cleanup;
    for (index = 0; index < count; ++index)
        paths[index] = (const uint8_t *)objects[index];
    roots = input_runtime_roots(target, paths, count);
cleanup:
    for (index = 0; objects && index < count; ++index) {
        if (objects[index]) unlink(objects[index]);
        free(objects[index]);
    }
    free(objects);
    free(paths);
    rmdir(directory);
    return roots;
}

uint64_t native_host_runtime_roots(uint32_t target,
                                   const struct native_c_source_path *sources,
                                   const uint8_t *const *inputs,
                                   uintptr_t input_count) {
    uint64_t roots = source_runtime_roots(target, sources);
    uint64_t input_roots;
    if (roots == UINT64_MAX || (input_count && !inputs)) return UINT64_MAX;
    input_roots = input_runtime_roots(target, inputs, input_count);
    if (input_roots == UINT64_MAX) return UINT64_MAX;
    return roots | input_roots;
}

static int valid_link_input(const char *path, uint32_t kind, uint32_t target) {
    const char *dot;
    if (!path || access(path, R_OK) != 0) return 0;
    if (kind != 1) return 1;
    dot = strrchr(path, '.');
    return dot && (strcasecmp(dot, ".o") == 0 ||
                   (target == NATIVE_TARGET_X86_64_WINDOWS &&
                    strcasecmp(dot, ".obj") == 0));
}

static const char *default_freestanding_script(uint32_t target) {
    const char *directory = getenv("PSL_LINKER_DIR");
    static char path[4096];
    const char *name = target == NATIVE_TARGET_X86_64_NONE ?
        "x86_64-linux-user.ld" : "riscv64-virt.ld";
    int length;
    if (!directory || !*directory) directory = "linker";
    length = snprintf(path, sizeof path, "%s/%s", directory, name);
    return length >= 0 && (size_t)length < sizeof path ? path : NULL;
}

static int link_freestanding(const uint8_t *path,
                             const struct byte_buffer *object,
                             const struct native_c_source_path *sources,
                             uint32_t target, uint32_t profile,
                             uint64_t runtime_modules, uint32_t kind,
                             const uint8_t *const *inputs, uintptr_t input_count,
                             const uint8_t *entry, const uint8_t *linker_script,
                             const uint8_t *map_file) {
    const char *linker = target_linker(target);
    const char *script = linker_script ? (const char *)linker_script :
        default_freestanding_script(target);
    const char *entry_name = entry ? (const char *)entry : "_start";
    char *directory = NULL, *map_directory = NULL;
    char *stage_output = NULL, *stage_map = NULL;
    char **arguments = NULL;
    size_t capacity, map_capacity = 0, count = 0, index;
    char *object_path = NULL;
    int ok = 0;
    if (!path || !object || !linker || !script || kind != 0 || profile != 0 ||
        runtime_modules != 0 || source_count(sources) != 0 ||
        (input_count && !inputs) ||
        (map_file && strcmp((const char *)path, (const char *)map_file) == 0) ||
        access(script, R_OK) != 0)
        return 0;
    for (index = 0; index < input_count; ++index)
        if (!valid_link_input((const char *)inputs[index], kind, target)) return 0;
    directory = output_temporary_directory((const char *)path);
    if (!directory) goto cleanup;
    capacity = strlen(directory) + sizeof "/artifact";
    if (map_file) {
        map_directory = output_temporary_directory((const char *)map_file);
        if (!map_directory) goto cleanup;
        map_capacity = strlen(map_directory) + sizeof "/link.map";
    }
    stage_output = calloc(capacity, 1);
    object_path = calloc(capacity, 1);
    if (map_file) stage_map = calloc(map_capacity, 1);
    arguments = calloc(input_count + 16, sizeof *arguments);
    if (!stage_output || !object_path || (map_file && !stage_map) || !arguments)
        goto cleanup;
    if (!format_path(stage_output, capacity, directory, "artifact") ||
        !format_path(object_path, capacity, directory, "psl.o") ||
        !write_object(object_path, object)) goto cleanup;
    if (map_file && !format_path(stage_map, map_capacity, map_directory, "link.map"))
        goto cleanup;
    arguments[count++] = (char *)linker;
    arguments[count++] = "-nostdlib";
    arguments[count++] = "-static";
    arguments[count++] = "--build-id=none";
    arguments[count++] = "--fatal-warnings";
    arguments[count++] = "-e";
    arguments[count++] = (char *)entry_name;
    arguments[count++] = "-T";
    arguments[count++] = (char *)script;
    if (map_file) {
        arguments[count++] = "-Map";
        arguments[count++] = stage_map;
    }
    arguments[count++] = "-o";
    arguments[count++] = stage_output;
    arguments[count++] = object_path;
    for (index = 0; index < input_count; ++index)
        arguments[count++] = (char *)inputs[index];
    arguments[count] = NULL;
    if (!run_tool(arguments)) goto cleanup;
    if (map_file && rename(stage_map, (const char *)map_file) != 0) goto cleanup;
    if (rename(stage_output, (const char *)path) != 0) goto cleanup;
    ok = 1;
cleanup:
    if (stage_output) unlink(stage_output);
    if (stage_map) unlink(stage_map);
    if (object_path) unlink(object_path);
    if (directory) rmdir(directory);
    if (map_directory) rmdir(map_directory);
    free(arguments); free(stage_output); free(stage_map); free(object_path);
    free(directory); free(map_directory);
    return ok;
}

static int compile_link_object(const char *compiler, const char *source,
                               const char *object, int pic) {
    char *arguments[9];
    size_t count = 0;
    arguments[count++] = (char *)compiler;
    arguments[count++] = "-std=c11";
    arguments[count++] = "-fno-stack-protector";
    if (pic) arguments[count++] = "-fPIC";
    arguments[count++] = "-c";
    arguments[count++] = (char *)source;
    arguments[count++] = "-o";
    arguments[count++] = (char *)object;
    arguments[count] = NULL;
    return run_tool(arguments);
}

enum { NATIVE_RUNTIME_MODULE_COUNT = 11 };

static const char *runtime_filename(unsigned bit, uint32_t target) {
    switch (bit) {
    case 0: return "value.c";
    case 1: return "cons.c";
    case 2: return "string.c";
    case 3: return "symbol.c";
    case 4: return "package.c";
    case 5: return "closure.c";
    case 6: return "values.c";
    case 7: return "gc.c";
    case 8: return "startup.c";
    case 9:
        return target == NATIVE_TARGET_X86_64_WINDOWS ?
            "platform_windows.c" : "platform_linux.c";
    case 10: return "vector.c";
    default: return NULL;
    }
}

static uint64_t runtime_bit(unsigned bit) {
    static const uint64_t values[] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024};
    return bit < sizeof values / sizeof *values ? values[bit] : 0;
}

int native_host_link_artifact(const uint8_t *path,
                              const struct byte_buffer *object,
                              const struct native_c_source_path *sources,
                              uint32_t target, uint32_t profile,
                              uint64_t runtime_modules, uint32_t kind,
                              const uint8_t *const *inputs,
                              uintptr_t input_count, uint32_t startup_kind,
                              const uint8_t *entry,
                              const uint8_t *linker_script,
                              const uint8_t *map_file) {
    const char *compiler = target_compiler(target);
    const char *archiver = target_archiver(target);
    const char *requested_name = output_file_name((const char *)path);
    uintptr_t source_count_value = source_count(sources);
    size_t capacity, count = 0, index;
    char *directory = NULL, *stage_directory = NULL, *stage_output = NULL;
    const char *stage_name;
    char *psl_object = NULL, **objects = NULL;
    char **runtime_objects = NULL, **arguments = NULL;
    int ok = 0, use_runtime;
    (void)profile;
    if (target == NATIVE_TARGET_X86_64_NONE || target == NATIVE_TARGET_RISCV64_NONE) {
        (void)startup_kind;
        return link_freestanding(path, object, sources, target, profile,
                                 runtime_modules, kind, inputs, input_count,
                                 entry, linker_script, map_file);
    }
    if (!path || !object || !compiler || !requested_name || kind > 2 ||
        (input_count && !inputs) || (kind == 1 && !archiver) ||
        (runtime_modules & ~((UINT64_C(1) << NATIVE_RUNTIME_MODULE_COUNT) - 1))) return 0;
    for (index = 0; index < input_count; ++index)
        if (!valid_link_input((const char *)inputs[index], kind, target)) return 0;
    use_runtime = runtime_modules != 0;
    stage_name = kind == 1 ? "artifact.a" :
        (target == NATIVE_TARGET_X86_64_WINDOWS && kind == 0 ?
         "artifact.exe" : requested_name);
    directory = output_temporary_directory((const char *)path);
    stage_directory = output_temporary_directory((const char *)path);
    if (!directory || !stage_directory) goto cleanup;
    capacity = strlen(directory) + 64;
    psl_object = calloc(capacity, 1);
    objects = calloc(source_count_value ? source_count_value : 1, sizeof *objects);
    runtime_objects = calloc(NATIVE_RUNTIME_MODULE_COUNT, sizeof *runtime_objects);
    {
        size_t directory_length = strlen(stage_directory);
        size_t name_length = strlen(stage_name);
        if (directory_length > SIZE_MAX - name_length - 2) goto cleanup;
        stage_output = calloc(directory_length + name_length + 2, 1);
    }
    if (!psl_object || !objects || !runtime_objects || !stage_output)
        goto cleanup;
    if (!format_path(psl_object, capacity, directory, "psl.o") ||
        !format_path(stage_output, strlen(stage_directory) + strlen(stage_name) + 2,
                     stage_directory, stage_name) ||
        !write_object(psl_object, object)) goto cleanup;
    if (!compile_sources(compiler, sources, directory, objects,
                         (size_t)source_count_value, target)) goto cleanup;
    {
        const char *runtime_directory = getenv("PSL_RUNTIME_DIR");
        if (!runtime_directory || !*runtime_directory) runtime_directory = "runtime";
        for (index = 0; index < NATIVE_RUNTIME_MODULE_COUNT; ++index) {
            uint64_t bit = runtime_bit((unsigned)index);
            const char *filename = runtime_filename((unsigned)index, target);
            char *source_path;
            if (!(runtime_modules & bit) || !filename) continue;
            source_path = calloc(strlen(runtime_directory) + strlen(filename) + 2, 1);
            runtime_objects[index] = calloc(capacity, 1);
            if (!source_path || !runtime_objects[index]) {
                free(source_path);
                goto cleanup;
            }
            sprintf(source_path, "%s/%s", runtime_directory, filename);
            snprintf(runtime_objects[index], capacity, "%s/runtime-%u.o",
                     directory, (unsigned)index);
            if (!compile_link_object(compiler, source_path,
                                     runtime_objects[index],
                                     kind == 2 || target != NATIVE_TARGET_X86_64_WINDOWS)) {
                free(source_path);
                goto cleanup;
            }
            free(source_path);
        }
    }
    {
        size_t runtime_count = 0;
        char **link_objects;
        size_t item_count = 1 + input_count + source_count_value + NATIVE_RUNTIME_MODULE_COUNT;
        link_objects = calloc(item_count, sizeof *link_objects);
        if (!link_objects) goto cleanup;
        link_objects[runtime_count++] = psl_object;
        for (index = 0; index < NATIVE_RUNTIME_MODULE_COUNT; ++index)
            if (runtime_objects[index]) link_objects[runtime_count++] = runtime_objects[index];
        for (index = 0; index < source_count_value; ++index)
            link_objects[runtime_count++] = objects[index];
        for (index = 0; index < input_count; ++index)
            link_objects[runtime_count++] = (char *)inputs[index];
        if (kind == 1) {
            arguments = calloc(runtime_count + 4, sizeof *arguments);
            if (!arguments) { free(link_objects); goto cleanup; }
            arguments[count++] = (char *)archiver;
            arguments[count++] = "rcsD";
            arguments[count++] = stage_output;
            for (index = 0; index < runtime_count; ++index)
                arguments[count++] = link_objects[index];
            arguments[count] = NULL;
            ok = run_tool(arguments);
        } else {
            arguments = calloc(runtime_count + 10, sizeof *arguments);
            if (!arguments) { free(link_objects); goto cleanup; }
            arguments[count++] = (char *)compiler;
            if (use_runtime && target != NATIVE_TARGET_X86_64_WINDOWS)
                arguments[count++] = "-pthread";
            if (kind == 2) arguments[count++] = "-shared";
            arguments[count++] = "-o";
            arguments[count++] = stage_output;
            for (index = 0; index < runtime_count; ++index)
                arguments[count++] = link_objects[index];
            arguments[count] = NULL;
            ok = run_tool(arguments);
        }
        free(link_objects);
    }
    if (!ok || rename(stage_output, (const char *)path) != 0) ok = 0;
cleanup:
    if (objects) {
        for (index = 0; index < source_count_value; ++index) {
            if (objects[index]) unlink(objects[index]);
            free(objects[index]);
        }
    }
    if (runtime_objects)
        for (index = 0; index < NATIVE_RUNTIME_MODULE_COUNT; ++index) {
            if (runtime_objects[index]) unlink(runtime_objects[index]);
            free(runtime_objects[index]);
        }
    if (psl_object) unlink(psl_object);
    if (stage_output) unlink(stage_output);
    if (directory) rmdir(directory);
    if (stage_directory) rmdir(stage_directory);
    free(objects); free(runtime_objects); free(arguments);
    free(psl_object); free(stage_output);
    free(directory); free(stage_directory);
    return ok;
}

int native_host_merge_c_sources(const uint8_t *output,
                                const struct byte_buffer *object,
                                const struct native_c_source_path *sources,
                                uint32_t target) {
    const char *compiler = target_compiler(target);
    size_t count = source_count(sources);
    char *directory, *psl, *merged;
    char **objects;
    size_t path_capacity;
    int ok = 0;
    if (!compiler || !count) return 0;
    directory = output_temporary_directory((const char *)output);
    if (!directory) return 0;
    path_capacity = strlen(directory) + sizeof "/merged.o";
    psl = calloc(path_capacity, 1);
    merged = calloc(path_capacity, 1);
    objects = calloc(count, sizeof *objects);
    if (psl && merged && objects &&
        format_path(psl, path_capacity, directory, "psl.o") &&
        format_path(merged, path_capacity, directory, "merged.o") &&
        write_object(psl, object) &&
        compile_sources(compiler, sources, directory, objects, count, target) &&
        merge_objects(compiler, merged, psl, objects, count))
        ok = rename(merged, (const char *)output) == 0;
    remove_temporary_files(objects, count, psl, merged, directory);
    free(objects);
    free(psl);
    free(merged);
    free(directory);
    return ok;
}
#else
int native_host_link_supported(void) {
    return 0;
}

uint64_t native_host_runtime_roots(uint32_t target,
                                   const struct native_c_source_path *sources,
                                   const uint8_t *const *inputs,
                                   uintptr_t input_count) {
    (void)target;
    (void)sources;
    (void)inputs;
    (void)input_count;
    return UINT64_MAX;
}

int native_host_link_artifact(const uint8_t *path,
                              const struct byte_buffer *object,
                              const struct native_c_source_path *sources,
                              uint32_t target, uint32_t profile,
                              uint64_t runtime_modules, uint32_t kind,
                              const uint8_t *const *inputs,
                              uintptr_t input_count, uint32_t startup_kind,
                              const uint8_t *entry,
                              const uint8_t *linker_script,
                              const uint8_t *map_file) {
    (void)path;
    (void)object;
    (void)sources;
    (void)target;
    (void)profile;
    (void)runtime_modules;
    (void)kind;
    (void)inputs;
    (void)input_count;
    (void)startup_kind;
    (void)entry;
    (void)linker_script;
    (void)map_file;
    return 0;
}

int native_host_merge_c_sources(const uint8_t *output,
                                const struct byte_buffer *object,
                                const struct native_c_source_path *sources,
                                uint32_t target) {
    (void)output;
    (void)object;
    (void)sources;
    (void)target;
    return 0;
}
#endif
