#include "../native_api.h"
#include "compiler.h"
#include "source.h"
#include <stdint.h>

#if defined(__unix__) || defined(__APPLE__)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

static void remove_temporary_files(char **objects, size_t count,
                                   const char *psl, const char *merged,
                                   const char *directory) {
    size_t index;
    for (index = 0; index < count; ++index) {
        if (objects[index]) unlink(objects[index]);
        free(objects[index]);
    }
    unlink(psl);
    unlink(merged);
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
                           size_t count) {
    size_t index;
    for (index = 0; index < count; ++index, source = source->next) {
        size_t length = strlen(directory) + 32;
        int written;
        char *arguments[6];
        objects[index] = malloc(length);
        if (!objects[index]) return 0;
        written = snprintf(objects[index], length, "%s/c%zu.o", directory,
                           index);
        if (written < 0 || (size_t)written >= length)
            return 0;
        arguments[0] = (char *)compiler;
        arguments[1] = "-c";
        arguments[2] = (char *)source->path;
        arguments[3] = "-o";
        arguments[4] = objects[index];
        arguments[5] = NULL;
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

int native_host_merge_c_sources(const uint8_t *output,
                                const struct byte_buffer *object,
                                const struct native_c_source_path *sources,
                                uint32_t target) {
    char directory[] = "/tmp/psl-native-XXXXXX";
    const char *compiler = target_compiler(target);
    char psl[sizeof directory + 16] = {0};
    char merged[sizeof directory + 16] = {0};
    size_t count = source_count(sources);
    char **objects;
    int ok = 0;
    if (!compiler || !count || !mkdtemp(directory)) return 0;
    objects = calloc(count, sizeof *objects);
    if (!objects) {
        rmdir(directory);
        return 0;
    }
    if (format_path(psl, sizeof psl, directory, "psl.o") &&
        format_path(merged, sizeof merged, directory, "merged.o") &&
        write_object(psl, object) &&
        compile_sources(compiler, sources, directory, objects, count) &&
        merge_objects(compiler, merged, psl, objects, count))
        ok = rename(merged, (const char *)output) == 0;
    remove_temporary_files(objects, count, psl, merged, directory);
    free(objects);
    return ok;
}
#else
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
