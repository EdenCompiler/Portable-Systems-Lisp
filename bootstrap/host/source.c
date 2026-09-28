#ifndef _WIN32
#define _XOPEN_SOURCE 700
#endif
#include "source.h"
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
#endif

uint8_t *native_source_canonical_path(const uint8_t *path) {
#ifdef _WIN32
    char *absolute = _fullpath(NULL, (const char *)path, 0);
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
    return (uint8_t *)result;
#else
    return (uint8_t *)realpath((const char *)path, NULL);
#endif
}

/* Platform policy is queried by the hosted PSL path helper, not the frontend. */
int native_source_windows_paths(void) {
#ifdef _WIN32
    return 1;
#else
    return 0;
#endif
}

void native_source_report_error(uint32_t kind, const uint8_t *path) {
    const char *message;
    switch (kind) {
    case 1: message = "cannot read source"; break;
    case 2: message = "circular source include"; break;
    case 3: message = "invalid include form"; break;
    case 4: message = "reader error"; break;
    default: return;
    }
    fprintf(stderr, "%s: %s\n", message, (const char *)path);
}
