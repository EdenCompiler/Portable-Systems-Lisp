#include "compiler.h"
#include "../native_api.h"
#include <inttypes.h>
#include <stdio.h>

int native_host_write_object(const uint8_t *path, const struct byte_buffer *object) {
    FILE *stream = fopen((const char *)path, "wb");
    int result;
    if (!stream) return 0;
    result = fwrite(object->data, 1, object->length, stream) == object->length;
    if (fclose(stream) != 0) result = 0;
    return result;
}

void native_host_report_error(uint32_t kind, const uint8_t *text,
                              uintptr_t length, uintptr_t position) {
    switch (kind) {
    case NATIVE_HOST_READ:
        fprintf(stderr, "cannot read source: %s\n", (const char *)text); break;
    case NATIVE_HOST_ALLOCATE:
        fputs("cannot allocate compiler buffers\n", stderr); break;
    case NATIVE_HOST_UNSUPPORTED:
        fprintf(stderr, "unsupported or malformed source: %s\n", (const char *)text); break;
    case NATIVE_HOST_WRITE:
        fprintf(stderr, "cannot write object: %s\n", (const char *)text); break;
    case NATIVE_HOST_USAGE:
        fputs("usage: pslcc-native-slice [-O0|-O1] SOURCE.lisp OUTPUT.o\n", stderr); break;
    case NATIVE_HOST_LAYOUT:
        fprintf(stderr, "cannot register layout at byte %" PRIuPTR "\n", position); break;
    case NATIVE_HOST_IMPORT:
        fprintf(stderr, "cannot parse C import at byte %" PRIuPTR "\n", position); break;
    case NATIVE_HOST_DECLARATION:
        fprintf(stderr, "cannot parse declaration at byte %" PRIuPTR "\n", position); break;
    case NATIVE_HOST_PREDECLARATION:
        fprintf(stderr, "cannot predeclare function at byte %" PRIuPTR "\n", position); break;
    case NATIVE_HOST_BODY:
        fputs("cannot compile function: ", stderr);
        fwrite(text, 1, length, stderr);
        fputc('\n', stderr);
        break;
    case NATIVE_HOST_ALLOCATION_EFFECT:
        fputs("WITHOUT-ALLOCATION cannot certify call to ", stderr);
        fwrite(text, 1, length, stderr);
        fputc('\n', stderr);
        break;
    default: break;
    }
}
