#include "../bootstrap/native_api.h"
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static const char source[] =
    "(defmacro m (x) (list 'wrap+ x x))\n"
    "(defun nested_result () (declare (returns u64) (c-export :c)) "
    "(m (m (m (m 1)))))\n";

static int overflow_prepare_is_clean(void) {
    struct native_driver driver = {0};
    driver.source = malloc(2);
    if (!driver.source) return 0;
    memcpy(driver.source, "x", 2);
    driver.length = 1;
    int prepared = native_prepare_driver_capacity(&driver, SIZE_MAX);
    int released = native_release_driver(&driver);
    int released_again = native_release_driver(&driver);
    return !prepared && released && released_again && !driver.source;
}

static int fixed_capacity_remains_fixed(void) {
    struct native_driver driver = {0};
    const size_t length = sizeof source - 1;
    driver.source = malloc(length + 1);
    if (!driver.source) return 0;
    memcpy(driver.source, source, length + 1);
    driver.length = length;
    if (!native_prepare_driver(&driver)) {
        native_release_driver(&driver);
        return 0;
    }
    if (driver.parser.capacity != length + 1) {
        native_release_driver(&driver);
        return 0;
    }
    uint8_t bytes[8] = {0xa5, 0x5a, 0x12, 0x34, 0, 0, 0, 0};
    struct byte_buffer object = {bytes, 4, sizeof bytes};
    struct native_unit_result result = {0};
    int compiled = native_compile_unit(&driver.context, &object, &result);
    int capacity_failure = !compiled &&
        driver.context.macro_call.error == NATIVE_MACRO_SYNTAX_CAPACITY;
    int bytes_preserved = bytes[0] == 0xa5 && bytes[1] == 0x5a &&
        bytes[2] == 0x12 && bytes[3] == 0x34;
    native_release_driver(&driver);
    native_release_driver(&driver);
    return capacity_failure && bytes_preserved;
}

int main(void) {
    assert(overflow_prepare_is_clean());
    assert(fixed_capacity_remains_fixed());
    return 0;
}
