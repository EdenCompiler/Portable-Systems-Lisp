#ifndef PSL_BOOTSTRAP_HOST_COMPILER_H
#define PSL_BOOTSTRAP_HOST_COMPILER_H
#include <stdint.h>
struct byte_buffer;

/* Rendering codes chosen by the PSL driver, independent of compiler phases. */
enum native_host_error_kind {
    NATIVE_HOST_READ = 1, NATIVE_HOST_ALLOCATE, NATIVE_HOST_UNSUPPORTED,
    NATIVE_HOST_WRITE, NATIVE_HOST_USAGE, NATIVE_HOST_LAYOUT,
    NATIVE_HOST_IMPORT, NATIVE_HOST_DECLARATION, NATIVE_HOST_PREDECLARATION,
    NATIVE_HOST_BODY
};
int native_host_write_object(const uint8_t *path, const struct byte_buffer *object);
void native_host_report_error(uint32_t kind, const uint8_t *text,
                              uintptr_t length, uintptr_t position);
#endif
