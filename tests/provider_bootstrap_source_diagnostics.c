#include "../bootstrap/host/source.h"
#include <stdio.h>

/* Isolated source-loader tests provide the diagnostic callback that the full
   native compiler supplies from bootstrap/host/diagnostics.lisp. */
void native_source_report_error(uint32_t kind, const uint8_t *path) {
    const char *message;
    switch (kind) {
    case 1: message = "cannot read source"; break;
    case 2: message = "circular source include"; break;
    case 3: message = "invalid include form"; break;
    case 4: message = "reader error"; break;
    case 5: message = "duplicate C source"; break;
    default: return;
    }
    fprintf(stderr, "%s: %s\n", message, (const char *)path);
}
