#include "../bootstrap/host/source.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef EXPECT_WINDOWS_PATHS
#define EXPECT_WINDOWS_PATHS 0
#endif

int main(int argc, char **argv) {
    assert(argc == 4);
    uint8_t *first = native_source_canonical_path((const uint8_t *)argv[1]);
    uint8_t *second = native_source_canonical_path((const uint8_t *)argv[2]);
    assert(first && second && strcmp((const char *)first, (const char *)second) == 0);
    assert(!native_source_canonical_path((const uint8_t *)argv[3]));
    assert(native_source_windows_paths() == EXPECT_WINDOWS_PATHS);
    free(first);
    free(second);
    puts("PSL hosted canonical path and platform policy passed");
    return 0;
}
