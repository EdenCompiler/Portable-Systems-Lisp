#ifndef _WIN32
#define _XOPEN_SOURCE 700
#endif
#include "source.h"
#include "../native_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#endif

struct source_file {
    char *path;
    int active;
    struct source_file *next;
};

struct source_unit {
    uint8_t *bytes;
    size_t length, capacity;
    struct source_file *files;
};

static uint8_t *read_file(const char *path, size_t *length) {
    FILE *stream = fopen(path, "rb");
    long size;
    uint8_t *bytes;
    if (!stream) return NULL;
    if (fseek(stream, 0, SEEK_END) != 0 || (size = ftell(stream)) < 0 ||
        fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    bytes = malloc((size_t)size + 1);
    if (!bytes || fread(bytes, 1, (size_t)size, stream) != (size_t)size) {
        free(bytes);
        fclose(stream);
        return NULL;
    }
    fclose(stream);
    bytes[size] = 0;
    *length = (size_t)size;
    return bytes;
}

static char *canonical_path(const char *path) {
#ifdef _WIN32
    char *absolute = _fullpath(NULL, path, 0);
    if (!absolute) return NULL;
    HANDLE file = CreateFileA(absolute, 0, FILE_SHARE_READ | FILE_SHARE_WRITE |
                              FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    free(absolute);
    if (file == INVALID_HANDLE_VALUE) return NULL;
    DWORD size = GetFinalPathNameByHandleA(file, NULL, 0, FILE_NAME_NORMALIZED);
    char *result = size ? malloc((size_t)size + 1) : NULL;
    DWORD written = result ? GetFinalPathNameByHandleA(file, result, size + 1,
                                                       FILE_NAME_NORMALIZED) : 0;
    CloseHandle(file);
    if (!written || written > size) { free(result); return NULL; }
    return result;
#else
    return realpath(path, NULL);
#endif
}

static char *include_path(const char *parent, const char *name) {
    int absolute = name[0] == '/';
#ifdef _WIN32
    absolute = absolute || name[0] == '\\' || (name[0] && name[1] == ':');
#endif
    if (absolute) {
        size_t size = strlen(name) + 1;
        char *result = malloc(size);
        if (result) memcpy(result, name, size);
        return result;
    }
    const char *slash = strrchr(parent, '/');
#ifdef _WIN32
    const char *backslash = strrchr(parent, '\\');
    if (backslash && (!slash || backslash > slash)) slash = backslash;
#endif
    size_t directory = slash ? (size_t)(slash - parent) + 1 : 0;
    size_t size = strlen(name) + 1;
    if (directory > SIZE_MAX - size) return NULL;
    char *result = malloc(directory + size);
    if (result) {
        memcpy(result, parent, directory);
        memcpy(result + directory, name, size);
    }
    return result;
}

static int append_form(struct source_unit *unit, const uint8_t *bytes, size_t size) {
    if (unit->length > SIZE_MAX - 2 || size > SIZE_MAX - unit->length - 2) return 0;
    size_t needed = unit->length + size + 2;
    if (unit->capacity < needed) {
        uint8_t *larger = realloc(unit->bytes, needed);
        if (!larger) return 0;
        unit->bytes = larger;
        unit->capacity = needed;
    }
    memcpy(unit->bytes + unit->length, bytes, size);
    unit->length += size;
    unit->bytes[unit->length++] = '\n';
    unit->bytes[unit->length] = 0;
    return 1;
}

static struct source_file *find_file(struct source_unit *unit, const char *path) {
    for (struct source_file *file = unit->files; file; file = file->next)
        if (strcmp(file->path, path) == 0) return file;
    return NULL;
}

static struct source_file *add_file(struct source_unit *unit, char *path) {
    struct source_file *file = calloc(1, sizeof *file);
    if (file) {
        file->path = path;
        file->active = 1;
        file->next = unit->files;
        unit->files = file;
    }
    return file;
}

static int load_file(struct source_unit *unit, const char *path);

static int load_include(struct source_unit *unit, const char *parent,
                         struct psl_parser *parser, const uint8_t *bytes,
                         uintptr_t root) {
    uintptr_t size = native_source_include_size(parser, bytes, root);
    uint8_t *name = malloc(size + 1);
    if (!name) return 0;
    int decoded = native_source_include_copy(parser, bytes, root, name, size + 1);
    char *path = decoded ? include_path(parent, (const char *)name) : NULL;
    free(name);
    if (!path) return 0;
    int result = load_file(unit, path);
    free(path);
    return result;
}

static int load_forms(struct source_unit *unit, const char *path,
                       const uint8_t *bytes, size_t length) {
    struct psl_ast_node *nodes = calloc(length + 1, sizeof *nodes);
    if (!nodes) return 0;
    struct psl_scanner scanner = {bytes, length, 0, 0};
    struct psl_token token = {0};
    struct psl_parser parser = {&scanner, &token, 0, nodes, 0, length + 1, 0};
    uintptr_t root;
    int result = 1;
    while ((root = parser_next(&parser)) != 0) {
        uint32_t kind = native_source_form_kind(&parser, bytes, root);
        if (kind == 2) result = load_include(unit, path, &parser, bytes, root);
        else if (kind == 1) {
            struct psl_ast_node *form = &nodes[root - 1];
            result = append_form(unit, bytes + form->start, form->length);
        } else {
            fprintf(stderr, "invalid include form: %s\n", path);
            result = 0;
        }
        if (!result) break;
    }
    result = result && parser.error == 0;
    if (parser.error) fprintf(stderr, "reader error: %s\n", path);
    free(nodes);
    return result;
}

static int load_new_file(struct source_unit *unit, struct source_file *file) {
    size_t length;
    uint8_t *bytes = read_file(file->path, &length);
    if (!bytes) {
        fprintf(stderr, "cannot read source: %s\n", file->path);
        return 0;
    }
    int result = load_forms(unit, file->path, bytes, length);
    free(bytes);
    file->active = 0;
    return result;
}

static int load_file(struct source_unit *unit, const char *path) {
    char *canonical = canonical_path(path);
    if (!canonical) {
        fprintf(stderr, "cannot read source: %s\n", path);
        return 0;
    }
    struct source_file *file = find_file(unit, canonical);
    if (file) {
        free(canonical);
        if (file->active) fprintf(stderr, "circular source include: %s\n", file->path);
        return !file->active;
    }
    file = add_file(unit, canonical);
    if (!file) { free(canonical); return 0; }
    return load_new_file(unit, file);
}

static void release_files(struct source_unit *unit) {
    struct source_file *file = unit->files;
    while (file) {
        struct source_file *next = file->next;
        free(file->path);
        free(file);
        file = next;
    }
}

uint8_t *native_read_source_unit(const char *path, size_t *length) {
    struct source_unit unit = {0};
    int result = load_file(&unit, path);
    release_files(&unit);
    if (!result) { free(unit.bytes); return NULL; }
    *length = unit.length;
    if (!unit.bytes) unit.bytes = calloc(1, 1);
    return unit.bytes;
}
