#ifndef PSL_BOOTSTRAP_HOST_SOURCE_H
#define PSL_BOOTSTRAP_HOST_SOURCE_H
#include <stddef.h>
#include <stdint.h>

/* PSL owns traversal, deduplication, cycles, parsing, and assembled bytes.
   Returned source/canonical buffers are owned and free-compatible. */
uint8_t *native_read_source_unit(const char *path, size_t *length);
/* Implemented by the separately compiled PSL source input unit. */
uint8_t *native_source_read_file(const uint8_t *path, size_t *length);
/* Implemented by the selected separately compiled PSL path unit. */
uint8_t *native_source_canonical_path(const uint8_t *path);
int native_source_windows_paths(void);
/* Temporary diagnostic adapter imported by the PSL loader. */
void native_source_report_error(uint32_t kind, const uint8_t *path);
#endif
