#include "native_api.h"

/* The native PSL driver owns argument validation and compilation flow. */
int main(int argc, char **argv) {
    return native_compiler_main(argc, argv);
}
