#include "native_api.h"
#include "host/source.h"
#include <stdio.h>

static int write_object(const char *path, const struct byte_buffer *object) {
    FILE *stream = fopen(path, "wb");
    int result;

    if (!stream) return 0;
    result = fwrite(object->data, 1, object->length, stream) == object->length;
    if (fclose(stream) != 0) result = 0;
    return result;
}

static void report_unit_error(const struct native_driver *d,
                               const struct native_unit_result *result) {
    const char *message = NULL;
    switch (result->phase) {
    case NATIVE_UNIT_LAYOUT: message = "cannot register layout"; break;
    case NATIVE_UNIT_IMPORT: message = "cannot parse C import"; break;
    case NATIVE_UNIT_SIGNATURE: message = "cannot parse declaration"; break;
    case NATIVE_UNIT_PREDECLARE: {
        uintptr_t name = d->storage.signatures[result->index].name;
        fprintf(stderr, "cannot predeclare function at byte %lu\n",
                (unsigned long)d->parser.nodes[name - 1].start);
        return;
    }
    case NATIVE_UNIT_BODY: {
        const struct native_function *function = &d->storage.functions[result->index];
        fprintf(stderr, "cannot compile function: %.*s\n",
                (int)function->name_length, function->name);
        return;
    }
    default: return;
    }
    fprintf(stderr, "%s at byte %lu\n", message,
            (unsigned long)d->parser.nodes[result->form - 1].start);
}

static int run_compiler(const char *source_path, const char *output_path) {
    struct native_driver driver = {0};
    int result = 0;
    struct native_unit_result unit_result = {0};
    driver.source = native_read_source_unit(source_path, &driver.length);
    if (!driver.source) {
        fprintf(stderr, "cannot read source: %s\n", source_path);
        return 2;
    }
    if (!native_prepare_driver(&driver)) {
        fprintf(stderr, "cannot allocate compiler buffers\n");
        result = 2;
    } else if (!native_compile_unit(&driver.context, &driver.object, &unit_result)) {
        report_unit_error(&driver, &unit_result);
        fprintf(stderr, "unsupported or malformed source: %s\n", source_path);
        result = 1;
    } else if (!write_object(output_path, &driver.object)) {
        fprintf(stderr, "cannot write object: %s\n", output_path);
        result = 2;
    }
    native_release_driver(&driver);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: pslcc-native-slice SOURCE.lisp OUTPUT.o\n");
        return 2;
    }
    return run_compiler(argv[1], argv[2]);
}
