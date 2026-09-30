#ifndef PSL_BOOTSTRAP_HOST_SOURCE_H
#define PSL_BOOTSTRAP_HOST_SOURCE_H
#include <stddef.h>
#include <stdint.h>

struct native_c_source_path {
    uint8_t *path;
    struct native_c_source_path *next;
};

/* PSL owns traversal, deduplication, cycles, parsing, and assembled bytes.
   Returned source/canonical buffers and C-source list are free-compatible. */
uint8_t *native_read_source_unit(const char *path, size_t *length,
                                 struct native_c_source_path **c_sources);
/* Implemented by the separately compiled PSL source input unit. */
uint8_t *native_source_read_file(const uint8_t *path, size_t *length);
/* Implemented by the selected separately compiled PSL path unit. */
uint8_t *native_source_canonical_path(const uint8_t *path);
int native_source_windows_paths(void);
/* Implemented by the separately compiled PSL diagnostic unit. */
void native_source_report_error(uint32_t kind, const uint8_t *path);
#endif
