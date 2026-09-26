#ifndef PSL_BOOTSTRAP_HOST_SOURCE_H
#define PSL_BOOTSTRAP_HOST_SOURCE_H
#include <stddef.h>
#include <stdint.h>

/* Temporary OS boundary. Parser decisions and string decoding stay in PSL. */
uint8_t *native_read_source_unit(const char *path, size_t *length);
#endif
